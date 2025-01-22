#!/usr/bin/env python3
"""
Convert YOLO models to Core ML format.
Usage: ./convert_yolo.py [v8|11] [n|s|m|l|x]
Default: v8 n (YOLOv8 nano model)
"""

import os
import sys
from ultralytics import YOLO


def main():
    # Create ultralytics directory if it doesn't exist
    if not os.path.exists("ultralytics"):
        print("Creating ultralytics directory...")
        os.makedirs("ultralytics")

    # Default to YOLOv8 nano model if no arguments provided
    version = sys.argv[1] if len(sys.argv) > 1 else "v8"
    size = sys.argv[2] if len(sys.argv) > 2 else "n"

    # Validate version
    if version not in ["v8", "11"]:
        print(f"Invalid YOLO version: {version}")
        print("Valid versions: v8, 11")
        sys.exit(1)

    # Validate model size
    if size not in ["n", "s", "m", "l", "x"]:
        print(f"Invalid model size: {size}")
        print("Valid sizes: n (nano), s (small), m (medium), l (large), x (xlarge)")
        sys.exit(1)

    # Format model name based on version
    model_name = f"yolo{version}{size}"
    if version == "11":
        model_name = f"yolo11{size}"  # YOLO11 format
    else:
        model_name = f"yolov8{size}"  # YOLOv8 format

    print(f"Converting {model_name} model...")

    # Download and load the model from Ultralytics hub
    model = YOLO(f"ultralytics/{model_name}")

    # Export to Core ML format
    model.export(format="coreml", nms=True)

    print(f"Done! Model saved as {model_name}.mlpackage")


if __name__ == "__main__":
    main()
