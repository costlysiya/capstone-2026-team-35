import requests

BASE = "http://127.0.0.1:8000/api"

test_cases = [
    {
        "name": "기프티콘",
        "ocr_text": "카카오프렌즈 춘식이 인형\n유효기간: 2026.12.31\n교환처: 카카오프렌즈 매장",
        "expected_type": "SCHEDULE"
    },
    {
        "name": "맛집",
        "ocr_text": "해운대 소문난 돼지국밥\n부산 해운대구 중동\n평점 4.3 | 리뷰 2,847개",
        "expected_type": "PLACE"
    },
    {
        "name": "쇼핑",
        "ocr_text": "애플 에어팟 프로 2세대\n359,000원 → 289,000원\n쿠팡 로켓배송",
        "expected_type": "WISHLIST"
    },
    {
        "name": "메모",
        "ocr_text": "2026학년도 2학기 수강신청 안내\n기간: 8월 18일 ~ 8월 22일\n학교 포털 사이트 참조",
        "expected_type": "SCHEDULE"  # 또는 MEMO (둘 다 가능)
    },
]

for tc in test_cases:
    resp = requests.post(f"{BASE}/analyze/v2", json={
        "ocr_text": tc["ocr_text"],
        "masked_tokens": []
    })
    result = resp.json()
    match = "✅" if result.get("type") == tc["expected_type"] else "❌"
    print(f"{match} [{tc['name']}] 예상: {tc['expected_type']} → 결과: {result.get('type')} (신뢰도: {result.get('confidence')})")
    print(f"   필드: {result.get('fields')}")
    print()
