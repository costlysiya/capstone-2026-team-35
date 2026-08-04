import pytest
from fastapi.testclient import TestClient
from app.main import app
import time

client = TestClient(app)

def test_async_batch_queue_and_polling(mocker):
    """
    Day 29-30 비동기 큐 및 상태 조회 폴링 통합 테스트
    """
    # 1. LLM 의도적 지연 및 목킹
    def mock_call_llm(system_prompt, user_text):
        time.sleep(0.1) # 실제로는 2~3초 걸리지만 테스트이므로 0.1초 딜레이
        if "MEMO" in system_prompt:
            return {"type": "MEMO", "confidence": 0.9}
        return {"body": "test memo"}
    
    mocker.patch("app.routers.analyze.call_llm", side_effect=mock_call_llm)
    
    # 2. 비동기 배치 요청 전송 (2건)
    payload = {
        "items": [
            {"ocr_text": "메모 1번입니다", "type": "MEMO", "masked_tokens": []},
            {"ocr_text": "메모 2번입니다", "type": "MEMO", "masked_tokens": []}
        ]
    }
    
    response = client.post("/api/analyze/batch/async", json=payload)
    assert response.status_code == 202
    
    data = response.json()
    assert "task_id" in data
    assert data["status"] == "PENDING"
    
    task_id = data["task_id"]
    
    # 3. 폴링 루프 (최대 3초 대기)
    max_retries = 10
    completed = False
    
    for _ in range(max_retries):
        status_resp = client.get(f"/api/tasks/{task_id}/status")
        assert status_resp.status_code == 200
        
        s_data = status_resp.json()
        
        if s_data["status"] == "COMPLETED":
            assert s_data["total"] == 2
            assert s_data["completed"] == 2
            assert s_data["failed"] == 0
            assert len(s_data["results"]) == 2
            completed = True
            break
        elif s_data["status"] == "ERROR":
            pytest.fail("Task ended with ERROR status")
            
        time.sleep(0.3)
        
    assert completed, "Background task did not complete in time"
