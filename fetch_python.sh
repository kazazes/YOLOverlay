#!/bin/bash

# This script downloads the Python-Apple-support release and installs the Python interpreter and packages.
# They are then embedded into the app bundle.

set -e

# Ensure Pyenv is available
if ! command -v pyenv &>/dev/null; then
    echo "Pyenv is not installed. Please install Pyenv before running this script."
    exit 1
fi

# Set the Python version to 3.11.6
PYTHON_VERSION=3.11.6

# Install the specified Python version using Pyenv
if ! pyenv versions | grep -q $PYTHON_VERSION; then
    pyenv install $PYTHON_VERSION
fi

# Set the local Python version to the specified version
pyenv local $PYTHON_VERSION

cd "$(dirname "$0")"

rm -rf python-macos/**/*
mkdir -p python-macos
cd python-macos

# Download the Python-Apple-support release
curl -L -o python-apple-support.tar.gz https://github.com/beeware/Python-Apple-support/releases/download/3.11-b3/Python-3.11-macOS-support.b3.tar.gz

# Extract the downloaded tarball
tar -xzf python-apple-support.tar.gz

# Clean up the downloaded and extracted files
rm -rf python-apple-support.tar.gz Python-Apple-support-3.11-b3 platform-site

# Create site-packages directory
mkdir -p python-stdlib/site-packages

# Install packages directly into site-packages
python3 -m pip install --upgrade pip wheel setuptools --target python-stdlib/site-packages --no-cache-dir
python3 -m pip install numpy ultralytics coremltools --target python-stdlib/site-packages --no-cache-dir

# Clean up source files that might cause import issues
find python-stdlib/site-packages -type d -name "tests" -exec rm -rf {} +
find python-stdlib/site-packages -type d -name "testing" -exec rm -rf {} +
find python-stdlib/site-packages -type d -name "*.egg-info" -exec rm -rf {} +

# Create the modulemap file with the specified content
cat <<EOL >Python.xcframework/macos-arm64_x86_64/Headers/module.modulemap
module Python {
    umbrella header "Python.h"
    export *
    link "Python"
}
EOL
