"""
Day 26 체크리스트 검증 스크립트
- 체크 1: 장소(PLACE) 텍스트 → keep_photo: False, map_ready: True/False 확인
- 체크 2: 쇼핑(WISHLIST) 텍스트 → keep_photo: True, 가격(문자열)이 숫자로 변환되었는지 확인
- 체크 3: 메모(MEMO) 텍스트 → keep_photo: False, title(제목)이 body 앞부분으로 자동 생성되었는지 확인
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
print("[체크 1] 장소(PLACE) 텍스트 처리")
place_req = {
    "ocr_text": "을지다락 ★4.5\n서울 중구 을지로 115",
    "type": "PLACE",
    "masked_tokens": [],
    "image_hash": f"place_{time.time()}"
}

s1, b1 = post_json("/analyze/v2", place_req)
if s1 == 200:
    fields = b1.get("fields", {})
    # PLACE 응답은 리스트(items)일 수 있으므로 단일/복수 모두 대응
    if isinstance(fields, dict) and "items" in fields:
        item = fields["items"][0]
    elif isinstance(fields, list):
        item = fields[0]
    else:
        item = fields

    keep_photo = item.get("keep_photo")
    map_ready = item.get("map_ready")
    category = item.get("category")
    print(f"  keep_photo: {keep_photo}, map_ready: {map_ready}, category: {category}")
    
    if keep_photo is False and map_ready is True and category:
        print("  ✅ 장소(PLACE) 보강 성공!")
        results.append(("체크 1: 장소(PLACE) 오토필", True))
    else:
        print("  ❌ 실패! 오토필 값이 예상과 다름")
        results.append(("체크 1: 장소(PLACE) 오토필", False))
else:
    print(f"  ❌ 에러: {s1}")
    results.append(("체크 1: 장소(PLACE) 오토필", False))


print("\n[체크 2] 쇼핑(WISHLIST) 텍스트 처리")
wishlist_req = {
    "ocr_text": "나이키 에어맥스 90\n₩129,000",
    "type": "WISHLIST",
    "masked_tokens": [],
    "image_hash": f"wishlist_{time.time()}"
}
s2, b2 = post_json("/analyze/v2", wishlist_req)
if s2 == 200:
    fields = b2.get("fields", {})
    if isinstance(fields, dict) and "items" in fields:
        item = fields["items"][0]
    elif isinstance(fields, list):
        item = fields[0]
    else:
        item = fields

    keep_photo = item.get("keep_photo")
    price = item.get("price_amount")
    
    print(f"  keep_photo: {keep_photo}, price_amount: {price} (type: {type(price).__name__})")
    
    if keep_photo is True and isinstance(price, (int, float)) and price == 129000:
        print("  ✅ 위시리스트(WISHLIST) 보강 성공!")
        results.append(("체크 2: 쇼핑(WISHLIST) 오토필", True))
    else:
        print("  ❌ 실패! 오토필 값이 예상과 다르거나 가격 변환 실패")
        results.append(("체크 2: 쇼핑(WISHLIST) 오토필", False))
else:
    print(f"  ❌ 에러: {s2}")
    results.append(("체크 2: 쇼핑(WISHLIST) 오토필", False))


print("\n[체크 3] 메모(MEMO) 텍스트 처리")
memo_req = {
    "ocr_text": "오늘 회의 내용 요약: 1. 프론트엔드 작업 금요일까지 완료. 2. 백엔드는 API 문서 최신화할 것.",
    "type": "MEMO",
    "masked_tokens": [],
    "image_hash": f"memo_{time.time()}"
}
s3, b3 = post_json("/analyze/v2", memo_req)
if s3 == 200:
    fields = b3.get("fields", {})
    if isinstance(fields, dict) and "items" in fields:
        item = fields["items"][0]
    elif isinstance(fields, list):
        item = fields[0]
    else:
        item = fields

    keep_photo = item.get("keep_photo")
    title = item.get("title")
    body = item.get("body")
    
    print(f"  keep_photo: {keep_photo}, title: '{title}'")
    print(f"  body: '{body[:30]}...'")
    
    if keep_photo is False and title and len(title) > 0:
        print("  ✅ 메모(MEMO) 보강 성공!")
        results.append(("체크 3: 메모(MEMO) 오토필", True))
    else:
        print("  ❌ 실패! 오토필 값이 예상과 다름")
        results.append(("체크 3: 메모(MEMO) 오토필", False))
else:
    print(f"  ❌ 에러: {s3}")
    results.append(("체크 3: 메모(MEMO) 오토필", False))

# ==================== 결과 요약 ====================
print("\n" + "=" * 60)
passed = sum(1 for _, ok in results if ok)
total_tests = len(results)
print(f"Day 26 체크리스트 결과: {passed}/{total_tests} 통과")
for name, ok in results:
    icon = "✅" if ok else "❌"
    print(f"  {icon} {name}")
print("=" * 60)

if passed < total_tests:
    sys.exit(1)
