from fastapi import FastAPI, HTTPException, UploadFile, File
from pydantic import BaseModel
from pathlib import Path
import tempfile
import logging
import boto3
import hashlib
from datetime import datetime, timedelta
from ultralytics import YOLO
import os
from dotenv import load_dotenv
import shutil
import json
import torch

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("model_service")

# Load environment variables from .env file
load_dotenv()

app = FastAPI(title="YOLOverlay Model Conversion Service")

# Initialize R2 client (S3-compatible)
s3_client = boto3.client(
    "s3",
    endpoint_url=os.getenv("R2_ENDPOINT_URL"),
    aws_access_key_id=os.getenv("R2_ACCESS_KEY_ID"),
    aws_secret_access_key=os.getenv("R2_SECRET_ACCESS_KEY"),
    region_name="auto",
)
S3_BUCKET = os.getenv("R2_BUCKET")
PRESIGNED_URL_EXPIRY = 3600  # 1 hour

def compute_model_hash(model_path: Path) -> str:
    """Compute a hash of the model file."""
    hasher = hashlib.sha256()
    with open(model_path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            hasher.update(chunk)
    return hasher.hexdigest()

def check_model_exists(model_hash: str) -> tuple[bool, str]:
    """Check if a model with the given hash exists in R2."""
    s3_key = f"models/{model_hash}.mlpackage.zip"
    try:
        s3_client.head_object(Bucket=S3_BUCKET, Key=s3_key)
        url = s3_client.generate_presigned_url(
            "get_object",
            Params={"Bucket": S3_BUCKET, "Key": s3_key},
            ExpiresIn=PRESIGNED_URL_EXPIRY,
        )
        logger.info(f"Found existing model with hash {model_hash}")
        logger.info(f"Generated presigned URL: {url}")
        return True, url
    except s3_client.exceptions.ClientError:
        logger.info(f"No existing model found with hash {model_hash}")
        return False, ""

def upload_to_s3(file_path: Path, model_hash: str) -> str:
    """Upload converted model to R2."""
    s3_key = f"models/{model_hash}.mlpackage.zip"
    try:
        # Create a zip file of the .mlpackage directory
        zip_path = file_path.parent / f"{file_path.stem}.zip"
        
        # Change to the parent directory of the .mlpackage to preserve structure
        original_dir = os.getcwd()
        os.chdir(file_path.parent)
        
        try:
            # Create zip archive from the .mlpackage directory itself
            shutil.make_archive(
                str(zip_path.with_suffix("")),  # Base name without .zip
                "zip",                          # Archive format
                root_dir=".",                   # Start from current directory
                base_dir=file_path.name         # Include only the .mlpackage directory
            )
            logger.info(f"Created zip archive at {zip_path}")
        finally:
            os.chdir(original_dir)  # Always restore original directory

        # Upload zip file to R2
        s3_client.upload_file(
            str(zip_path),
            S3_BUCKET,
            s3_key,
            ExtraArgs={"ContentType": "application/zip"},
        )
        logger.info(f"Uploaded zip file to R2: {s3_key}")

        # Generate presigned URL for download
        url = s3_client.generate_presigned_url(
            "get_object",
            Params={"Bucket": S3_BUCKET, "Key": s3_key},
            ExpiresIn=PRESIGNED_URL_EXPIRY,
        )
        logger.info(f"Generated presigned URL: {url}")
        return url
    except Exception as e:
        logger.exception("Failed to upload to R2")
        raise HTTPException(status_code=500, detail=f"Failed to upload model: {str(e)}")

def convert_to_coreml(model_path: Path, output_path: Path) -> Path:
    """Convert YOLO model to CoreML format using Ultralytics export."""
    try:
        logger.info(f"Starting model conversion: {model_path}")
        # Load the YOLO model
        model = YOLO(str(model_path))
        logger.info("Successfully loaded YOLO model")
        
        try:
            # Determine if model is segmentation or detection
            is_segmentation = hasattr(model.model, 'seg')
            logger.info(f"Model type: {'segmentation' if is_segmentation else 'detection'}")
            
            # Export to CoreML format with appropriate parameters
            logger.info("Exporting to CoreML format...")
            export_args = {
                "format": "coreml",
                "nms": True,
            }
            
            if is_segmentation:
                # Add segmentation-specific parameters
                export_args.update({
                    "nms": False,  # NMS not needed for segmentation
                    "mask_resolution": 160,  # Adjust based on your needs (160x160 is a good default)
                })
            
            model.export(**export_args)
            logger.info("Export completed")
            
            # Find the exported .mlpackage file
            mlpackage_files = list(model_path.parent.glob("*.mlpackage"))
            if not mlpackage_files:
                logger.error("No .mlpackage file found after export")
                raise ValueError("CoreML export failed - no .mlpackage file found")
                
            logger.info(f"Found exported file: {mlpackage_files[0]}")
            
            # Move to desired output path
            mlpackage_files[0].rename(output_path)
            logger.info(f"Moved exported file to: {output_path}")
            return output_path
        finally:
            # Clean up YOLO model
            logger.info("Cleaning up YOLO model...")
            del model
            import gc
            gc.collect()
            torch.cuda.empty_cache()  # Clear CUDA cache if available
            logger.info("YOLO model cleanup completed")
            
    except Exception as e:
        logger.exception("Failed to convert model")
        raise HTTPException(status_code=400, detail=f"Failed to convert model: {str(e)}")

class ModelResponse(BaseModel):
    """Response containing model download info."""
    download_url: str
    expires_at: datetime

    class Config:
        json_encoders = {
            # Format datetime as ISO8601 with timezone
            datetime: lambda v: v.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        }

@app.post("/upload", response_model=ModelResponse)
async def upload_model(model: UploadFile = File(...)):
    """Upload and convert a PyTorch YOLO model to CoreML format."""
    logger.info(f"Received upload request for file: {model.filename}")
    
    if not model.filename.endswith('.pt') and not model.filename.endswith('.pth'):
        logger.error(f"Invalid file type: {model.filename}")
        raise HTTPException(status_code=400, detail="Only PyTorch YOLO models (.pt or .pth) are supported")

    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            model_path = temp_path / model.filename
            logger.info(f"Created temporary directory: {temp_dir}")
            
            # Save uploaded file
            logger.info("Saving uploaded file...")
            with open(model_path, "wb") as f:
                content = await model.read()
                f.write(content)
            logger.info(f"Saved uploaded file: {model_path}")
            
            # Compute model hash
            model_hash = compute_model_hash(model_path)
            logger.info(f"Computed model hash: {model_hash}")
            
            # Check if model already exists
            exists, url = check_model_exists(model_hash)
            if exists:
                expires = datetime.utcnow() + timedelta(seconds=PRESIGNED_URL_EXPIRY)
                response = ModelResponse(
                    download_url=url,
                    expires_at=expires
                )
                logger.info(f"Returning cached model response: {json.dumps(response.dict(), default=str)}")
                return response
            
            # Convert model
            logger.info("Starting model conversion...")
            output_path = temp_path / f"{model_path.stem}.mlpackage"
            converted_path = convert_to_coreml(model_path, output_path)
            logger.info(f"Model converted successfully: {converted_path}")
            
            # Upload converted model
            logger.info("Uploading converted model...")
            url = upload_to_s3(converted_path, model_hash)
            
            expires = datetime.utcnow() + timedelta(seconds=PRESIGNED_URL_EXPIRY)
            response = ModelResponse(
                download_url=url,
                expires_at=expires
            )
            logger.info(f"Returning response: {json.dumps(response.dict(), default=str)}")
            return response
            
    except Exception as e:
        logger.exception("Failed to process model")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy"}
