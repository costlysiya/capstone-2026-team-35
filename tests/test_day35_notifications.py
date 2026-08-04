import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.database import save_notification

client = TestClient(app)

def test_notification_flow():
    test_token = "test_fcm_token_123"
    
    # 1. 토큰 등록
    resp = client.post("/api/notifications/token", json={"device_token": test_token})
    assert resp.status_code == 200
    assert "성공적으로 등록" in resp.json()["message"]
    
    # 2. 임의의 알림 백엔드에서 생성 (실제로는 스케줄러가 생성)
    noti_id_1 = save_notification(test_token, "일정 알림", "약속이 3시간 남았습니다.", result_id=10)
    noti_id_2 = save_notification(test_token, "기프티콘 알림", "스타벅스 쿠폰이 내일 만료됩니다.", result_id=15)
    
    # 3. 내 알림함 조회
    resp = client.get(f"/api/notifications?device_token={test_token}")
    assert resp.status_code == 200
    
    notis = resp.json()
    assert len(notis) >= 2
    
    # ORDER BY created_at DESC 이므로 최근 것이 먼저 옴 (noti_id_2)
    assert notis[0]["id"] == noti_id_2
    assert notis[0]["is_read"] == False
    assert notis[0]["result_id"] == 15
    
    # 4. 알림 읽음 처리
    resp = client.put(f"/api/notifications/{noti_id_2}/read")
    assert resp.status_code == 200
    
    # 5. 다시 조회 시 읽음 처리 반영 확인
    resp = client.get(f"/api/notifications?device_token={test_token}")
    notis = resp.json()
    assert notis[0]["is_read"] == True
    assert notis[1]["is_read"] == False
    
    # 6. 없는 알림 읽음 처리 시 404
    resp = client.put(f"/api/notifications/99999/read")
    assert resp.status_code == 404

def test_notification_invalid_token():
    resp = client.post("/api/notifications/token", json={"device_token": "   "})
    assert resp.status_code == 400
    
    resp = client.get(f"/api/notifications?device_token=")
    assert resp.status_code == 400
