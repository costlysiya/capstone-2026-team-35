"""
Day 25 체크리스트 검증 스크립트
- 체크 1: _enrich_schedule_fields() 로직 추가 확인
- 체크 2: 기프티콘 텍스트 처리 시 keep_photo: True, calendar_type: EXPIRY 확인
- 체크 3: 일반 약속 텍스트 처리 시 keep_photo: False, calendar_type: EVENT 확인
- 체크 4: 구독 텍스트 처리 시 keep_photo: False, calendar_type: RENEWAL 확인
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
print("[체크 2] 기프티콘 텍스트 처리")
gifticon_req = {
    "ocr_text": "[교환권] BBQ 황금올리브치킨+콜라1.25L\n유효기간: 2026.12.31\n바코드: 123456789012",
    "type": "SCHEDULE",
    "masked_tokens": [],
    "image_hash": f"gifticon_{time.time()}"
}

s1, b1 = post_json("/analyze/v2", gifticon_req)
if s1 == 200:
    fields = b1.get("fields", {})
    sub_type = fields.get("sub_type")
    keep_photo = fields.get("keep_photo")
    cal_type = fields.get("calendar_type")
    print(f"  sub_type: {sub_type}, keep_photo: {keep_photo}, calendar_type: {cal_type}")
    
    if keep_photo is True and cal_type == "EXPIRY":
        print("  ✅ 기프티콘 처리 성공!")
        results.append(("체크 2: 기프티콘 오토필", True))
    else:
        print("  ❌ 실패! 오토필 값이 예상과 다름")
        results.append(("체크 2: 기프티콘 오토필", False))
else:
    print(f"  ❌ 에러: {s1}")
    results.append(("체크 2: 기프티콘 오토필", False))


print("\n[체크 3] 일반 약속(미팅) 텍스트 처리")
appt_req = {
    "ocr_text": "내일 오후 3시에 강남역 4번 출구 앞에서 봐요~",
    "type": "SCHEDULE",
    "masked_tokens": [],
    "image_hash": f"appt_{time.time()}"
}
s2, b2 = post_json("/analyze/v2", appt_req)
if s2 == 200:
    fields = b2.get("fields", {})
    sub_type = fields.get("sub_type")
    keep_photo = fields.get("keep_photo")
    cal_type = fields.get("calendar_type")
    print(f"  sub_type: {sub_type}, keep_photo: {keep_photo}, calendar_type: {cal_type}")
    
    if keep_photo is False and cal_type == "EVENT":
        print("  ✅ 일반 약속 처리 성공!")
        results.append(("체크 3: 일반 약속 오토필", True))
    else:
        print("  ❌ 실패! 오토필 값이 예상과 다름")
        results.append(("체크 3: 일반 약속 오토필", False))
else:
    print(f"  ❌ 에러: {s2}")
    results.append(("체크 3: 일반 약속 오토필", False))


print("\n[체크 4] 구독 만료 텍스트 처리")
subs_req = {
    "ocr_text": "넷플릭스 프리미엄 멤버십 결제 예정 안내\n결제일: 2026.09.01\n금액: 17,000원",
    "type": "SCHEDULE",
    "masked_tokens": [],
    "image_hash": f"subs_{time.time()}"
}
s3, b3 = post_json("/analyze/v2", subs_req)
if s3 == 200:
    fields = b3.get("fields", {})
    sub_type = fields.get("sub_type")
    keep_photo = fields.get("keep_photo")
    cal_type = fields.get("calendar_type")
    recurrence = fields.get("recurrence")
    reminders = fields.get("reminder_days")
    print(f"  sub_type: {sub_type}, keep_photo: {keep_photo}, cal: {cal_type}, recurrence: {recurrence}")
    print(f"  reminders: {reminders}")
    
    if keep_photo is False and cal_type == "RENEWAL" and recurrence == "매월" and 30 in reminders:
        print("  ✅ 구독 만료 처리 성공!")
        results.append(("체크 4: 구독 만료 오토필", True))
    else:
        print("  ❌ 실패! 오토필 값이 예상과 다름")
        results.append(("체크 4: 구독 만료 오토필", False))
else:
    print(f"  ❌ 에러: {s3}")
    results.append(("체크 4: 구독 만료 오토필", False))

# ==================== 결과 요약 ====================
print("\n" + "=" * 60)
passed = sum(1 for _, ok in results if ok)
total_tests = len(results)
print(f"Day 25 체크리스트 결과: {passed}/{total_tests} 통과")
for name, ok in results:
    icon = "✅" if ok else "❌"
    print(f"  {icon} {name}")
print("=" * 60)

if passed < total_tests:
    sys.exit(1)
