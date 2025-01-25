from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, HttpUrl
from pathlib import Path
import tempfile
import logging
import boto3
import requests
import hashlib
from datetime import datetime, timedelta
from ultralytics import YOLO  # type: ignore
import os
from dotenv import load_dotenv
import shutil

# Load environment variables from .env file
load_dotenv()

app = FastAPI(title="YOLOverlay Model Conversion Service")
logger = logging.getLogger("model_service")

# Initialize R2 client (S3-compatible)
s3_client = boto3.client(
    "s3",
    endpoint_url=os.getenv("R2_ENDPOINT_URL"),
    aws_access_key_id=os.getenv("R2_ACCESS_KEY_ID"),
    aws_secret_access_key=os.getenv("R2_SECRET_ACCESS_KEY"),
    region_name="auto",  # R2 uses 'auto' region
)
S3_BUCKET = os.getenv("R2_BUCKET")
PRESIGNED_URL_EXPIRY = 3600  # 1 hour


def compute_model_hash(model_path: Path, model_params: dict) -> str:
    """Compute a hash of the model file and its parameters."""
    hasher = hashlib.sha256()

    # Hash the model file content
    with open(model_path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            hasher.update(chunk)

    # Hash the model parameters
    params_str = str(sorted(model_params.items()))
    hasher.update(params_str.encode())

    return hasher.hexdigest()


def check_model_exists(model_hash: str) -> tuple[bool, str]:
    """Check if a model with the given hash exists in R2."""
    s3_key = f"models/{model_hash}.mlpackage.zip"

    try:
        s3_client.head_object(Bucket=S3_BUCKET, Key=s3_key)
        # Model exists, generate a new presigned URL
        url = s3_client.generate_presigned_url(
            "get_object",
            Params={"Bucket": S3_BUCKET, "Key": s3_key},
            ExpiresIn=PRESIGNED_URL_EXPIRY,
        )
        return True, url
    except s3_client.exceptions.ClientError:
        # If model doesn't exist, return False with empty URL
        return False, ""


def upload_to_s3(file_path: Path, model_hash: str) -> str:
    """Upload model to R2 using its hash as the key."""
    s3_key = f"models/{model_hash}.mlpackage.zip"

    try:
        # Create a zip file of the .mlpackage directory
        zip_path = file_path.parent / f"{file_path.stem}.zip"
        shutil.make_archive(str(zip_path.with_suffix("")), "zip", file_path)

        # Upload zip file to R2
        s3_client.upload_file(
            str(zip_path),
            S3_BUCKET,
            s3_key,
            ExtraArgs={"ContentType": "application/zip"},
        )

        # Generate presigned URL for download
        url = s3_client.generate_presigned_url(
            "get_object",
            Params={"Bucket": S3_BUCKET, "Key": s3_key},
            ExpiresIn=PRESIGNED_URL_EXPIRY,
        )

        return url
    except Exception as e:
        logger.exception("Failed to upload to R2")
        raise HTTPException(status_code=500, detail=f"Failed to upload model: {str(e)}")


def download_from_github(url: str, temp_path: Path, token: str | None = None) -> Path:
    """Download a model file from GitHub."""
    # Convert github.com URL to raw.githubusercontent.com
    if "github.com" in url:
        url = url.replace("github.com", "raw.githubusercontent.com")
        if "/blob/" in url:
            url = url.replace("/blob/", "/")

    logger.info(f"Downloading model from GitHub: {url}")
    headers = {"Authorization": f"token {token}"} if token else {}
    response = requests.get(url, stream=True, headers=headers)

    if response.status_code == 401:
        raise HTTPException(
            status_code=401, detail="Authentication failed - check your token"
        )
    elif response.status_code == 403:
        raise HTTPException(
            status_code=403,
            detail="Access forbidden - private repository requires a valid token",
        )
    elif response.status_code != 200:
        raise HTTPException(
            status_code=400, detail=f"Failed to download model: {response.status_code}"
        )

    # Save to temporary file
    model_path = temp_path / "model.pt"
    with open(model_path, "wb") as f:
        for chunk in response.iter_content(chunk_size=8192):
            f.write(chunk)

    return model_path


def get_hf_download_url(url: str) -> str:
    """Convert a Hugging Face model page URL to a direct download URL."""
    # Example input: https://huggingface.co/Ultralytics/YOLO11/blob/main/yolo11m.pt
    # Example output: https://huggingface.co/Ultralytics/YOLO11/resolve/main/yolo11m.pt

    if "/blob/" in url:
        return url.replace("/blob/", "/resolve/")
    return url


def download_from_huggingface(
    url: str, temp_path: Path, token: str | None = None
) -> Path:
    """Download a model file from Hugging Face."""
    # Convert model page URL to download URL if needed
    download_url = get_hf_download_url(url)
    logger.info(f"Downloading model from Hugging Face: {download_url}")

    headers = {"Authorization": f"Bearer {token}"} if token else {}
    response = requests.get(download_url, stream=True, headers=headers)

    if response.status_code == 401:
        raise HTTPException(
            status_code=401, detail="Authentication failed - check your token"
        )
    elif response.status_code == 403:
        raise HTTPException(
            status_code=403,
            detail="Access forbidden - private repository requires a valid token",
        )
    elif response.status_code == 404:
        raise HTTPException(
            status_code=400,
            detail="Failed to download model: File not found",
        )
    elif response.status_code != 200:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to download model: HTTP {response.status_code}",
        )

    # Save to temporary file
    model_path = temp_path / "model.pt"
    with open(model_path, "wb") as f:
        for chunk in response.iter_content(chunk_size=8192):
            f.write(chunk)

    return model_path


class ModelRequest(BaseModel):
    url: HttpUrl
    source: str = "huggingface"  # or "github"
    name: str | None = None
    token: str | None = None  # Add token field for authentication

    @property
    def display_url(self) -> str:
        """Return a display-friendly version of the URL."""
        url_str = str(self.url)
        # For HF URLs, show the model page URL instead of the download URL
        if self.source == "huggingface" and "/resolve/" in url_str:
            return url_str.replace("/resolve/", "/blob/")
        return url_str


class ModelMetadata(BaseModel):
    """Metadata about the converted model."""

    name: str
    description: str
    num_classes: int
    class_labels: list[str]
    created_at: datetime
    file_size: int
    source_url: str


class ModelResponse(BaseModel):
    """Response containing model download info and metadata."""

    download_url: str
    expires_at: datetime
    metadata: ModelMetadata


@app.post("/convert", response_model=ModelResponse)
async def convert_model(request: ModelRequest):
    """Convert a PyTorch YOLO model to CoreML format."""

    try:
        # Create temp directory for processing
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)

            try:
                # Download model from HF/GH
                if request.source == "huggingface":
                    download_url = get_hf_download_url(str(request.url))
                    try:
                        if request.token:
                            model_path = download_from_huggingface(
                                download_url, temp_path, request.token
                            )
                        else:
                            model_path = temp_path / "model.pt"
                            model = YOLO(download_url)  # Use converted URL here
                            model.save(model_path)
                    except Exception as e:
                        if "UnpicklingError" in str(e) or "invalid load key" in str(e):
                            raise HTTPException(
                                status_code=400,
                                detail="Failed to download model: Invalid file format",
                            )
                        elif "TypeError" in str(
                            e
                        ) and "should be a *.pt PyTorch model" in str(e):
                            raise HTTPException(
                                status_code=400,
                                detail="Invalid file type",
                            )
                        else:
                            raise HTTPException(
                                status_code=400,
                                detail=f"Failed to download model: {str(e)}",
                            )
                elif request.source == "github":
                    model_path = download_from_github(
                        str(request.url), temp_path, request.token
                    )
                else:
                    raise HTTPException(
                        status_code=400,
                        detail="Invalid source. Must be 'huggingface' or 'github'",
                    )

                # Compute model hash including export parameters
                model_params = {
                    "format": "coreml",
                    "nms": True,
                    "source": request.source,
                    "url": str(request.url),
                }
                model_hash = compute_model_hash(model_path, model_params)

                # Check if model already exists
                exists, cached_url = check_model_exists(model_hash)
                if exists:
                    logger.info(
                        f"Model {model_hash} already exists, returning cached version"
                    )
                    name = request.name or f"yolo_model_{model_hash[:8]}"
                    model = YOLO(str(model_path))

                    metadata = ModelMetadata(
                        name=name,
                        description=f"YOLO model converted from {request.url} (cached)",
                        num_classes=len(model.names),
                        class_labels=list(model.names.values()),
                        created_at=datetime.utcnow(),
                        file_size=model_path.stat().st_size,
                        source_url=str(request.url),
                    )

                    return ModelResponse(
                        download_url=cached_url,
                        expires_at=datetime.utcnow()
                        + timedelta(seconds=PRESIGNED_URL_EXPIRY),
                        metadata=metadata,
                    )

                # Load and export model
                model = YOLO(str(model_path))
                name = request.name or f"yolo_model_{model_hash[:8]}"

                logger.info(f"Exporting model to CoreML format: {name}")

                # Export with correct parameters
                model.export(
                    format="coreml",
                    nms=True,  # Include NMS
                    imgsz=640,  # Required image size
                    verbose=False,
                )

                # Find the exported file - it will be in the same directory as model_path
                exported_files = list(temp_path.glob("*.mlpackage"))
                if not exported_files:
                    raise HTTPException(
                        status_code=500,
                        detail="Model export failed - CoreML package not created",
                    )

                # Rename the exported file to our desired name
                exported_path = temp_path / f"{name}.mlpackage"
                exported_files[0].rename(exported_path)

                # Upload to R2 using model hash
                download_url = upload_to_s3(exported_path, model_hash)
                expires_at = datetime.utcnow() + timedelta(seconds=PRESIGNED_URL_EXPIRY)

                # Create metadata
                metadata = ModelMetadata(
                    name=name,
                    description=f"YOLO model converted from {request.url}",
                    num_classes=len(model.names),
                    class_labels=list(model.names.values()),
                    created_at=datetime.utcnow(),
                    file_size=exported_path.stat().st_size,
                    source_url=str(request.url),
                )

                return ModelResponse(
                    download_url=download_url, expires_at=expires_at, metadata=metadata
                )

            except HTTPException:
                # Re-raise HTTP exceptions with their original status codes
                raise
            except Exception as e:
                logger.exception("Model conversion failed")
                raise HTTPException(status_code=500, detail=str(e))

    except Exception as e:
        if isinstance(e, HTTPException):
            raise
        logger.exception("Model conversion failed")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy"}
