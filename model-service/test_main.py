import pytest  # Required for test discovery and running
from fastapi.testclient import TestClient
from datetime import datetime
from main import app

client = TestClient(app)


def test_yolo11_conversion():
    """Test converting YOLO11 model from Hugging Face."""

    # Test model URL
    model_url = "https://huggingface.co/Ultralytics/YOLO11/blob/main/yolo11m.pt"

    # Make the request
    response = client.post(
        "/convert",
        json={
            "url": model_url,
            "source": "huggingface",
            "name": "yolo11m",
        },
    )

    # Check response status
    assert response.status_code == 200

    # Validate response structure
    data = response.json()
    assert "download_url" in data
    assert "expires_at" in data
    assert "metadata" in data

    # Validate metadata
    metadata = data["metadata"]
    assert metadata["name"] == "yolo11m"
    assert "YOLO model converted from" in metadata["description"]
    assert metadata["source_url"] == model_url
    assert isinstance(metadata["num_classes"], int)
    assert isinstance(metadata["class_labels"], list)
    assert len(metadata["class_labels"]) == metadata["num_classes"]
    assert isinstance(metadata["created_at"], str)
    assert isinstance(metadata["file_size"], int)

    # Validate URL format
    assert data["download_url"].startswith("https://")
    assert ".r2.cloudflarestorage.com" in data["download_url"]
    assert ".mlpackage.zip?" in data["download_url"]

    # Check expiry time format
    expires_at = datetime.fromisoformat(data["expires_at"].replace("Z", "+00:00"))
    assert expires_at > datetime.utcnow()


def test_invalid_model_url():
    """Test error handling for invalid model URL."""

    response = client.post(
        "/convert",
        json={
            "url": "https://huggingface.co/Ultralytics/YOLO11/blob/main/nonexistent.pt",
            "source": "huggingface",
        },
    )

    assert response.status_code == 400
    assert "Failed to download model" in response.json()["detail"]


def test_non_pt_file():
    """Test error handling for non-PyTorch file."""

    response = client.post(
        "/convert",
        json={
            "url": "https://huggingface.co/Ultralytics/YOLO11/blob/main/README.md",
            "source": "huggingface",
        },
    )

    assert response.status_code == 400
    # Check if either message format is present
    error_msg = response.json()["detail"]
    assert any(
        msg in error_msg
        for msg in ["Invalid file type", "should be a *.pt PyTorch model"]
    )
