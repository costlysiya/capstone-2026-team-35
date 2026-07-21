"""
4주차 통합 테스트 스크립트 (Day 28)
- 시나리오 1: 배치 분석 (/api/analyze/batch)
- 시나리오 2: 캐시 히트 (같은 해시로 2번 요청)
- 시나리오 3: sub_type별 오토필 (기프티콘, 구독, 장소, 쇼핑 등)
- 시나리오 4: 마스킹 정보 구조화
"""
import urllib.request
import json
import sys
import time

BASE = "http://127.0.0.1:8000/api"

def post_json(path: str, data: dict) -> tuple[int, dict]:
    body = json.dumps(data).encode("utf-8")
    req = urllib.request.Request(
        f"{BASE}{path}",
        data=body,
        headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as res:
            return res.status, json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode("utf-8"))

results = []
print("=" * 60)
print("🚀 4주차 전체 통합 테스트를 시작합니다.")
print("=" * 60)

# ---------------------------------------------------------
# 시나리오 1: 배치 분석 (Day 22)
# ---------------------------------------------------------
print("\n[시나리오 1] 배치 분석 테스트")
batch_req = {
    "items": [
        {"ocr_text": "첫번째 텍스트", "type": "MEMO", "masked_tokens": []},
        {"ocr_text": "두번째 텍스트", "type": "MEMO", "masked_tokens": []},
        {"ocr_text": "세번째 텍스트", "type": "MEMO", "masked_tokens": []}
    ]
}
s1, b1 = post_json("/analyze/batch", batch_req)
if s1 == 200 and b1.get("total") == 3 and b1.get("success") == 3:
    print("  ✅ 3개 항목 배치 분석 성공")
    results.append(("시나리오 1: 배치 분석", True))
else:
    print(f"  ❌ 배치 분석 실패: status={s1}")
    results.append(("시나리오 1: 배치 분석", False))


# ---------------------------------------------------------
# 시나리오 2: 캐시 히트 (Day 23)
# ---------------------------------------------------------
print("\n[시나리오 2] 캐시 히트 테스트")
test_hash = f"test_cache_hash_{time.time()}"
cache_req = {
    "ocr_text": "캐시 테스트용 텍스트입니다.",
    "type": "MEMO",
    "masked_tokens": [],
    "image_hash": test_hash
}
start1 = time.time()
s2_1, b2_1 = post_json("/analyze/v2", cache_req)
elapsed1 = time.time() - start1

start2 = time.time()
s2_2, b2_2 = post_json("/analyze/v2", cache_req)
elapsed2 = time.time() - start2

if s2_1 == 200 and s2_2 == 200:
    id1 = b2_1.get("id")
    id2 = b2_2.get("id")
    is_fast = elapsed2 < 2.0
    if id1 == id2 and is_fast:
        print(f"  ✅ 캐시 히트 성공 (소요시간 단축: {elapsed1:.2f}s -> {elapsed2:.2f}s)")
        results.append(("시나리오 2: 캐시 히트", True))
    else:
        print(f"  ❌ 캐시 히트 실패 (id 일치: {id1==id2}, 시간 단축: {is_fast})")
        results.append(("시나리오 2: 캐시 히트", False))
else:
    print("  ❌ 캐시 히트 API 호출 실패")
    results.append(("시나리오 2: 캐시 히트", False))


# ---------------------------------------------------------
# 시나리오 3: sub_type별 오토필 (Day 25, 26)
# ---------------------------------------------------------
print("\n[시나리오 3-1] 기프티콘 오토필")
gift_req = {
    "ocr_text": "[교환권] BBQ 치킨 기프티콘\n유효기간: 2026.12.31",
    "type": "SCHEDULE",
    "masked_tokens": [],
    "image_hash": f"gift_{time.time()}"
}
s3_1, b3_1 = post_json("/analyze/v2", gift_req)
if s3_1 == 200:
    fields = b3_1.get("fields", {})
    if fields.get("sub_type") == "GIFTICON" and fields.get("keep_photo") is True and fields.get("calendar_type") == "EXPIRY":
        print("  ✅ 기프티콘 오토필 성공 (keep_photo=True, EXPIRY)")
        results.append(("시나리오 3-1: 기프티콘", True))
    else:
        print("  ❌ 기프티콘 오토필 값 불일치")
        results.append(("시나리오 3-1: 기프티콘", False))
else:
    print("  ❌ 기프티콘 API 호출 실패")
    results.append(("시나리오 3-1: 기프티콘", False))


print("\n[시나리오 3-2] 구독 만료 오토필")
subs_req = {
    "ocr_text": "넷플릭스 프리미엄 결제 안내\n결제일: 2026.09.01",
    "type": "SCHEDULE",
    "masked_tokens": [],
    "image_hash": f"subs_{time.time()}"
}
s3_2, b3_2 = post_json("/analyze/v2", subs_req)
if s3_2 == 200:
    fields = b3_2.get("fields", {})
    if fields.get("sub_type") == "SUBSCRIPTION" and fields.get("recurrence") == "매월" and 30 in fields.get("reminder_days", []):
        print("  ✅ 구독 만료 오토필 성공 (recurrence=매월, reminder_days 포함)")
        results.append(("시나리오 3-2: 구독", True))
    else:
        print("  ❌ 구독 만료 오토필 값 불일치")
        results.append(("시나리오 3-2: 구독", False))
else:
    print("  ❌ 구독 API 호출 실패")
    results.append(("시나리오 3-2: 구독", False))


# ---------------------------------------------------------
# 시나리오 4: 마스킹 정보 구조화 (Day 27)
# ---------------------------------------------------------
print("\n[시나리오 4] 마스킹 정보 구조화")
mask_req = {
    "ocr_text": "카드 결제 1234-****-****-1234\n바코드: ************",
    "type": "MEMO",
    "masked_tokens": ["1234-1234-1234-1234", "1234567890123"],
    "image_hash": f"mask_{time.time()}"
}
s4, b4 = post_json("/analyze/v2", mask_req)
if s4 == 200:
    masked_info = b4.get("masked_info", [])
    types = {info.get("type") for info in masked_info}
    if {"CARD", "BARCODE"}.issubset(types):
        print("  ✅ 마스킹 구조화 성공 (CARD, BARCODE 감지)")
        results.append(("시나리오 4: 마스킹", True))
    else:
        print(f"  ❌ 마스킹 구조화 값 불일치: 감지된 타입 {types}")
        results.append(("시나리오 4: 마스킹", False))
else:
    print("  ❌ 마스킹 API 호출 실패")
    results.append(("시나리오 4: 마스킹", False))


# ==================== 최종 결과 요약 ====================
print("\n" + "=" * 60)
passed = sum(1 for _, ok in results if ok)
total = len(results)
print(f"🎉 4주차 통합 테스트 결과: {passed}/{total} 시나리오 통과")
for name, ok in results:
    icon = "✅" if ok else "❌"
    print(f"  {icon} {name}")
print("=" * 60)

if passed < total:
    sys.exit(1)
