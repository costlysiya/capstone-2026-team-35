import pytest
from unittest.mock import patch
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

@patch("app.routers.analyze.call_llm_with_limit")
def test_analyze_v2_memo_checklist_no_split(mock_call_llm_with_limit):
    call_count = 0
    def side_effect(*args, **kwargs):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            return {"type": "MEMO", "confidence": 0.9, "reasoning": "체크리스트"}
        else:
            return {
                "items": [
                    {"text": "장보기", "checked": False},
                    {"text": "빨래하기", "checked": False}
                ],
                "total_count": 2,
                "checked_count": 0
            }

    mock_call_llm_with_limit.side_effect = side_effect

    import uuid
    test_hash = f"memo_checklist_{uuid.uuid4().hex}"
    
    req_data = {
        "ocr_text": "1. 장보기\n2. 빨래하기",
        "image_hash": test_hash
    }

    resp = client.post("/api/analyze/v2", json=req_data)
    assert resp.status_code == 200
    
    data = resp.json()
    # MEMO는 리스트로 쪼개지지 않고 단일 객체로 반환되어야 함!
    assert isinstance(data, dict)
    assert data["type"] == "MEMO"
    
    fields = data["fields"]
    assert "items" in fields
    assert isinstance(fields["items"], list)
    assert len(fields["items"]) == 2
    assert fields["items"][0]["text"] == "장보기"
