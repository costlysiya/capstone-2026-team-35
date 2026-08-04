import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.database import save_result, get_db

client = TestClient(app)

@pytest.fixture(autouse=True)
def setup_teardown_db():
    """테스트용 더미 데이터 세팅"""
    # SQLite를 초기화하거나 더미 데이터를 넣습니다.
    # 여기서는 간단히 save_result로 데이터를 넣겠습니다.
    import json
    
    # 더미 데이터 삽입
    save_result("PLACE", 0.9, json.dumps({"name": "테스트카페", "category": "카페", "region": "서울 강남구"}))
    save_result("PLACE", 0.9, json.dumps({"name": "을지다락", "category": "양식", "region": "서울 중구"}))
    save_result("PLACE", 0.9, json.dumps({"name": "부산밀면", "category": "한식", "region": "부산 해운대구"}))
    
    memo_id = save_result("MEMO", 0.9, json.dumps({"title": "비밀번호 메모", "body": "내 비밀번호는 1234"}))
    
    # 메모는 CONFIRMED 상태로 업데이트해서 본문 가림 처리 확인
    conn = get_db()
    conn.execute("UPDATE screenshots SET status = 'CONFIRMED' WHERE id = ?", (memo_id,))
    conn.commit()
    conn.close()

    yield
    
    # Teardown (실제로는 테스트용 DB를 쓰거나 삭제해야 함. 간단히 전체 삭제)
    conn = get_db()
    conn.execute("DELETE FROM screenshots")
    conn.commit()
    conn.close()

def test_search_by_region_and_category():
    # 1. 지역 검색 테스트
    resp = client.get("/api/results?type=PLACE&region=서울")
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] >= 2
    
    # 서울을 포함하는 항목 필터링 검증
    seoul_items = [item for item in data["items"] if "서울" in item["fields"].get("region", "")]
    assert len(seoul_items) >= 2
    
    # 2. 카테고리 검색 테스트
    resp = client.get("/api/results?type=PLACE&category=카페")
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] >= 1
    
def test_search_pagination():
    # limit=1 로 페이지네이션 확인
    resp = client.get("/api/results?type=PLACE&limit=1&page=1")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["items"]) == 1
    assert data["total"] >= 3 # 전체는 3개 이상

def test_hide_memo_body_when_confirmed():
    # 메모 상세 조회
    # id를 알기 위해 리스트부터 조회
    resp = client.get("/api/results?type=MEMO")
    data = resp.json()
    
    # CONFIRMED 상태인 항목을 찾음
    memo_id = None
    for item in data["items"]:
        if item["status"] == "CONFIRMED":
            memo_id = item["id"]
            break
            
    if not memo_id:
        pytest.fail("CONFIRMED MEMO not found")
    
    detail_resp = client.get(f"/api/results/{memo_id}")
    assert detail_resp.status_code == 200
    detail_data = detail_resp.json()
    
    assert detail_data["status"] == "CONFIRMED"
    assert detail_data["fields"]["body"] == "[AI 분석 완료 - 원문 숨김 처리됨]"
