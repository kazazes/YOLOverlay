from ultralytics import YOLO
import coremltools as ct

# Download and load the YOLOv8n model
model = YOLO("yolov8n.pt")

# Export to Core ML format
model.export(format="coreml", nms=True)
