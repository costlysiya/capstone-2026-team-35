import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_classify_batch_success():
    req_data = {
        "items": [
            {"ocr_text": "토요일 6시에 강남역 11번 출구 고기집 예약했어", "type": None},
            {"ocr_text": "이 원피스 진짜 이쁘지 않냐? 39,000원이래", "type": None}
        ]
    }
    
    # Mocking `call_llm_with_limit` to avoid hitting real API during automated tests
    from unittest.mock import patch
    
    with patch("app.routers.analyze.call_llm_with_limit") as mock_call:
        # Mock 반환값 설정
        mock_call.side_effect = [
            {"type": "SCHEDULE", "confidence": 0.9, "reasoning": "시간과 약속(예약)이 포함됨"},
            {"type": "WISHLIST", "confidence": 0.8, "reasoning": "상품명과 가격이 포함됨"}
        ]
        
        resp = client.post("/api/classify/batch", json=req_data)
        
        assert resp.status_code == 200
        data = resp.json()
        
        assert data["total"] == 2
        assert len(data["results"]) == 2
        
        assert data["results"][0]["index"] == 0
        assert data["results"][0]["type"] == "SCHEDULE"
        
        assert data["results"][1]["index"] == 1
        assert data["results"][1]["type"] == "WISHLIST"

def test_classify_batch_limit():
    req_data = {
        "items": [{"ocr_text": "dummy"} for _ in range(51)]
    }
    
    resp = client.post("/api/classify/batch", json=req_data)
    assert resp.status_code == 400
    assert "최대 50개" in resp.json()["detail"]
