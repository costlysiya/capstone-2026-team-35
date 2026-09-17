import logging
logging.basicConfig(level=logging.INFO)
from fastapi.testclient import TestClient
from app.main import app
from unittest.mock import patch

client = TestClient(app)
call_count = 0

def side_effect(*args, **kwargs):
    global call_count
    call_count += 1
    print(f"MOCK CALL {call_count}: args={args}, kwargs={kwargs}")
    if call_count == 1:
        return {"type": "SCHEDULE"}
    return {"items": [{"title": "a"}]}

with patch("app.routers.analyze.call_llm_with_limit", side_effect=side_effect):
    client.post("/api/analyze/v2", json={"ocr_text": "test1", "image_hash": "test1"})
