"""YOLO wrapper for easier integration with Swift."""

import sys
import os


def init_numpy():
    """Initialize numpy carefully."""
    try:
        import numpy

        return True
    except ImportError as e:
        print(f"Failed to import numpy: {e}")
        return False


def init_ultralytics():
    """Initialize YOLO carefully."""
    try:
        from ultralytics import YOLO

        return YOLO
    except ImportError as e:
        print(f"Failed to import YOLO: {e}")
        return None


def get_paths():
    """Debug helper to print Python paths."""
    print("Python paths:")
    print(f"sys.path: {sys.path}")
    print(f"PYTHONPATH: {os.environ.get('PYTHONPATH')}")
    print(f"PYTHONHOME: {os.environ.get('PYTHONHOME')}")
    print(f"Current working directory: {os.getcwd()}")


def load_model(model_path):
    """Load a YOLO model with careful error handling."""
    get_paths()  # Print debug info

    if not init_numpy():
        raise ImportError("Failed to initialize numpy")

    YOLO = init_ultralytics()
    if YOLO is None:
        raise ImportError("Failed to initialize YOLO")

    try:
        return YOLO(model_path)
    except Exception as e:
        print(f"Error loading model: {e}")
        raise


def predict_image(model, image_path):
    """Run prediction on an image with error handling."""
    try:
        results = model.predict(image_path)
        return results[0]
    except Exception as e:
        print(f"Error during prediction: {e}")
        raise
