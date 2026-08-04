import pytest
from fastapi.testclient import TestClient
from app.main import app
from unittest.mock import patch

client = TestClient(app)

@patch("app.routers.analyze.call_llm_with_limit")
def test_analyze_v2_multi_split(mock_call_llm_with_limit):
    # 1. 1차 대분류 모킹 (SCHEDULE로 분류됨)
    # _classify_image 모킹 없이 v2 내부에서 call_llm_with_limit 2번 호출됨 (1차, 2차)
    call_count = 0
    def side_effect(*args, **kwargs):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            return {"type": "SCHEDULE", "confidence": 0.9, "reasoning": "다중 일정"}
        else:
            return {
                "items": [
                    {"title": "일정 1", "start_at": "2026-08-01"},
                    {"title": "일정 2", "expires_at": "2026-08-15"}
                ],
                "missing_fields": []
            }

    mock_call_llm_with_limit.side_effect = side_effect

    import uuid
    test_hash = f"multi_test_hash_{uuid.uuid4().hex}"
    
    # 2. V2 요청 (이미지 해시 포함)
    req_data = {
        "ocr_text": "일정1은 8월 1일, 일정2는 8월 15일까지",
        "image_hash": test_hash
    }

    resp = client.post("/api/analyze/v2", json=req_data)
    assert resp.status_code == 200
    
    # 3. 리스트 응답 검증
    data = resp.json()
    assert isinstance(data, list)
    assert len(data) == 2
    
    assert data[0]["type"] == "SCHEDULE"
    assert data[0]["fields"]["title"] == "일정 1"
    
    assert data[1]["type"] == "SCHEDULE"
    assert data[1]["fields"]["title"] == "일정 2"

    # 4. 동일 해시로 재요청 시 캐시에서 리스트 반환되는지 검증
    resp_cached = client.post("/api/analyze/v2", json=req_data)
    assert resp_cached.status_code == 200
    
    data_cached = resp_cached.json()
    assert isinstance(data_cached, list)
    assert len(data_cached) == 2
    assert data_cached[0]["id"] == data[0]["id"]
    assert data_cached[1]["id"] == data[1]["id"]
