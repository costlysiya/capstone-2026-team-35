import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.database import save_result
import json

client = TestClient(app)

def test_calendar_ical_generation():
    # 1. SCHEDULE 데이터 저장
    fields = {
        "title": "저녁 약속",
        "start_at": "2026-08-15",
        "start_time": "18:30",
        "exchange_place": "강남역",
        "description": "오랜만에 모임"
    }
    row_id = save_result(
        type="SCHEDULE",
        confidence=0.9,
        fields=json.dumps(fields),
        status="DRAFT"
    )

    # 2. 일반 단건 조회 API 확인 (ical_string 이 포함되는지)
    resp = client.get(f"/api/results/{row_id}")
    assert resp.status_code == 200
    data = resp.json()
    assert "ical_string" in data
    assert "BEGIN:VCALENDAR" in data["ical_string"]
    assert "DTSTART:20260815T183000" in data["ical_string"]
    assert "SUMMARY:저녁 약속" in data["ical_string"]

    # 3. ical 파일 다운로드 API 확인
    resp_ical = client.get(f"/api/results/{row_id}/ical")
    assert resp_ical.status_code == 200
    assert resp_ical.headers["content-type"] == "text/calendar; charset=utf-8"
    assert f'attachment; filename="schedule_{row_id}.ics"' in resp_ical.headers["content-disposition"]
    
    content = resp_ical.text
    assert "BEGIN:VEVENT" in content
    assert "LOCATION:강남역" in content

def test_calendar_ical_invalid_type():
    # 1. PLACE 데이터 저장
    fields = {"name": "뷰스트", "region": "제주 서귀포"}
    row_id = save_result(
        type="PLACE",
        confidence=0.9,
        fields=json.dumps(fields),
        status="DRAFT"
    )

    # 2. ical 다운로드 시도 시 에러 확인
    resp_ical = client.get(f"/api/results/{row_id}/ical")
    assert resp_ical.status_code == 400
    assert "일정(SCHEDULE) 타입만 캘린더 연동이 가능" in resp_ical.json()["detail"]
