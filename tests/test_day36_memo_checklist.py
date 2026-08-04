import pytest
import uuid
from unittest.mock import patch
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


@patch("app.routers.analyze.call_llm_with_limit")
def test_memo_checklist_single_card_and_key_rename(mock_call_llm_with_limit):
    """체크리스트는 분할 없이 단일 카드, items→checklist_items 키 변환 검증"""
    call_count = 0
    def side_effect(*args, **kwargs):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            return {"type": "MEMO", "confidence": 0.95, "reasoning": "체크리스트"}
        else:
            return {
                "fields": {
                    "title": "가족여행 준비물",
                    "body": "가족여행 준비물 목록",
                    "sub_type": "CHECKLIST",
                    "items": [
                        {"text": "냉장고 안 음료수", "checked": False},
                        {"text": "집 열쇠", "checked": False},
                        {"text": "충전기", "checked": True}
                    ],
                    "total_count": 3,
                    "checked_count": 1
                },
                "missing_fields": []
            }

    mock_call_llm_with_limit.side_effect = side_effect

    test_hash = f"checklist_{uuid.uuid4().hex}"
    resp = client.post("/api/analyze/v2", json={
        "ocr_text": "냉장고 안 음료수\n집 열쇠\n충전기",
        "image_hash": test_hash
    })
    assert resp.status_code == 200

    data = resp.json()
    # 1) 리스트가 아닌 단일 객체여야 한다 (분할 금지)
    assert isinstance(data, dict), f"MEMO 체크리스트가 리스트로 분할됨: {type(data)}"
    assert data["type"] == "MEMO"

    fields = data["fields"]
    # 2) items 키는 없어야 하고, checklist_items로 변환되어야 한다
    assert "items" not in fields, f"items 키가 아직 남아있음 (checklist_items로 변환 필요)"
    assert "checklist_items" in fields, f"checklist_items 키가 없음"
    assert len(fields["checklist_items"]) == 3
    assert fields["checklist_items"][0]["text"] == "냉장고 안 음료수"


@patch("app.routers.analyze.call_llm_with_limit")
def test_novel_title_uses_book_title(mock_call_llm_with_limit):
    """웹소설: LLM이 title을 본문으로 채워도 book_title이 무조건 우선"""
    call_count = 0
    def side_effect(*args, **kwargs):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            return {"type": "MEMO", "confidence": 0.9, "reasoning": "웹소설"}
        else:
            return {
                "fields": {
                    "title": "원래 이런 치졸한 외적 공격은 내게 전혀 통하지 않았는...",
                    "body": "원래 이런 치졸한 외적 공격은 내게 전혀 통하지 않았는데, 그건 내 원래 신체에 한한 일이었다는 걸 오늘 이 순간에 알았다.",
                    "sub_type": "NOVEL",
                    "book_title": "마법명가 차남으로 살아남는 법",
                    "author": "자연주의",
                    "platform": "카카오페이지",
                    "chapter": "453",
                    "genre": "기타"
                },
                "missing_fields": []
            }

    mock_call_llm_with_limit.side_effect = side_effect

    test_hash = f"novel_{uuid.uuid4().hex}"
    resp = client.post("/api/analyze/v2", json={
        "ocr_text": "원래 이런 치졸한 외적 공격은 내게 전혀...\n마법명가 차남으로 살아남는 법\n자연주의",
        "image_hash": test_hash
    })
    assert resp.status_code == 200

    data = resp.json()
    assert isinstance(data, dict)
    assert data["type"] == "MEMO"

    fields = data["fields"]
    # book_title이 title을 무조건 덮어써야 한다
    assert fields["title"] == "마법명가 차남으로 살아남는 법", \
        f"title이 book_title로 덮어쓰이지 않음: {fields['title']}"
    assert fields["book_title"] == "마법명가 차남으로 살아남는 법"
