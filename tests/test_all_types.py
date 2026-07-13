import urllib.request
import json
import sys

BASE = "http://127.0.0.1:8000/api"

def call_api(ocr_text: str) -> dict:
    """분석 API 호출"""
    data = json.dumps({"ocr_text": ocr_text, "masked_tokens": []}).encode("utf-8")
    req = urllib.request.Request(
        f"{BASE}/analyze/v2",
        data=data,
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=30) as res:
        return json.loads(res.read().decode("utf-8"))

# ==================== 정상 케이스 ====================

test_cases = [
    {
        "name": "✅ 기프티콘 (SCHEDULE)",
        "ocr_text": "[기프티콘] 투썸플레이스 스트로베리 라떼\n유효기간: 2026.09.30\n교환처: 투썸플레이스 전 매장\n바코드: 1234-5678-9012",
        "expected_type": "SCHEDULE"
    },
    {
        "name": "✅ 맛집 1곳 (PLACE)",
        "ocr_text": "을지다락 ★4.5\n서울 중구 을지로 115\n영업시간 11:00-22:00\n한식, 분위기 좋은 식당\n추천: 된장찌개, 제육볶음",
        "expected_type": "PLACE"
    },
    {
        "name": "✅ 맛집 여러 곳 (PLACE — 복수)",
        "ocr_text": "🏠 1.재경사\n🍀 대구 중구 큰장로28길 38-5\n🏠 2.압구정아이\n🍀 서문시장 2지구 서나10호\n🏠 3.마포상사\n🍀 대구 중구 큰장로28길 10\n🏠 4.경신상회\n🍀 대구 중구 큰장로28길 39",
        "expected_type": "PLACE"
    },
    {
        "name": "✅ 쇼핑 (WISHLIST)",
        "ocr_text": "나이키 에어맥스 90\n129,000원 → 89,900원 (30% 할인)\n무신사 | 무료배송\n사이즈: 270\n색상: 블랙/화이트",
        "expected_type": "WISHLIST"
    },
    {
        "name": "✅ 메모 (MEMO)",
        "ocr_text": "하루 물 2리터 마시기의 효과\n1. 피부 개선\n2. 신진대사 촉진\n3. 두통 예방\n- 출처: 헬스조선 2026.06.15",
        "expected_type": "MEMO"
    },
]

# ==================== 엣지 케이스 ====================

edge_cases = [
    {
        "name": "⚡ 빈 텍스트",
        "ocr_text": "",
        "check": lambda r: r.get("type") is not None  # 어떤 타입이든 반환
    },
    {
        "name": "⚡ 매우 짧은 텍스트",
        "ocr_text": "안녕",
        "check": lambda r: r.get("type") is not None
    },
    {
        "name": "⚡ 특수문자만",
        "ocr_text": "!!@#$%^&*()\n🎉🎊🥳",
        "check": lambda r: r.get("type") is not None
    },
    {
        "name": "⚡ 애매한 케이스 (일정+장소)",
        "ocr_text": "강남역 스타벅스에서 3시에 만나자\n토요일 오후 3시\n강남역 10번 출구 앞",
        "check": lambda r: r.get("type") in ("SCHEDULE", "PLACE")  # 둘 다 합리적
    },
    {
        "name": "⚡ 카카오톡 대화",
        "ocr_text": "지현: 이번 주 토요일 2시에 보자\n나: 어디서?\n지현: 홍대 카페 어때?\n나: 좋아 어디?\n지현: 연남동 카페꼼마 ㅎㅎ\n나: ㅋㅋ 거기 맛있어?",
        "check": lambda r: r.get("type") in ("SCHEDULE", "PLACE")
    },
]

# ==================== 실행 ====================

print("=" * 60)
print("🧪 소생 앱 API 종합 테스트")
print("=" * 60)

success = 0
fail = 0

# 정상 케이스
print("\n📋 정상 케이스:")
for tc in test_cases:
    try:
        result = call_api(tc["ocr_text"])
        is_match = result["type"] == tc["expected_type"]
        icon = "✅" if is_match else "❌"
        print(f"  {icon} [{tc['name']}]")
        print(f"     예상: {tc['expected_type']} → 결과: {result['type']} (신뢰도: {result['confidence']})")

        # 복수 항목 체크
        fields = result.get("fields", {})
        if "items" in fields:
            print(f"     📦 {len(fields['items'])}개 항목 추출됨")

        print(f"     상태: {result['status']} | 누락: {result.get('missing_fields', [])}")

        if is_match:
            success += 1
        else:
            fail += 1
    except Exception as e:
        print(f"  💥 [{tc['name']}] 에러: {e}")
        fail += 1

# 엣지 케이스
print("\n⚡ 엣지 케이스:")
for ec in edge_cases:
    try:
        result = call_api(ec["ocr_text"])
        passed = ec["check"](result)
        icon = "✅" if passed else "❌"
        print(f"  {icon} [{ec['name']}]")
        print(f"     결과: {result['type']} (신뢰도: {result['confidence']}) 상태: {result['status']}")

        if passed:
            success += 1
        else:
            fail += 1
    except Exception as e:
        print(f"  💥 [{ec['name']}] 에러: {e}")
        fail += 1

# 결과 요약
print("\n" + "=" * 60)
print(f"📊 결과: {success}개 성공 / {fail}개 실패 / 총 {success + fail}개")
print("=" * 60)

if fail > 0:
    sys.exit(1)
