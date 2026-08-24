import pytest
from fastapi.testclient import TestClient
from unittest.mock import MagicMock

# Set environment variable to avoid Postgres connection in test environment
import os
os.environ["DATABASE_URL"] = "sqlite:///:memory:"

from backend.app.main import app, get_db

client = TestClient(app)

def test_general_status():
    """Verify that the general health check endpoint responds correctly."""
    response = client.get("/api/v1/accessibility/status")
    assert response.status_code == 200
    json_data = response.json()
    assert json_data["status"] == "healthy"
    assert json_data["on_device_processing_status"] == "enabled"

def test_navigation_accessibility():
    """Verify that the navigation accessibility constraints meta endpoint responds correctly."""
    response = client.get("/api/v1/navigation/accessibility")
    assert response.status_code == 200
    json_data = response.json()
    assert json_data["status"] == "operational"
    assert "stairs" in json_data["routing_constraints"]

def test_mocked_register():
    """Verify register endpoint logic with a mocked DB session."""
    import datetime
    # Create a mock database session
    mock_db = MagicMock()
    mock_db.query.return_value.filter.return_value.first.return_value = None # No existing email

    # Mock add to assign properties so Pydantic serialization works
    def mock_add(obj):
        obj.id = 1
        obj.created_at = datetime.datetime.utcnow()
        obj.updated_at = datetime.datetime.utcnow()
        return None
    mock_db.add = mock_add

    # Override the database dependency
    app.dependency_overrides[get_db] = lambda: mock_db

    response = client.post("/api/v1/auth/register", json={
        "name": "Test User",
        "email": "test@accessibility.org",
        "password": "strongpassword123",
        "accessibility_mode": "visual"
    })
    
    # Check that database commit and add were called
    assert response.status_code == 201
    assert mock_db.commit.called
    
    # Clear overrides
    app.dependency_overrides.clear()

