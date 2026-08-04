"""
Day 23 체크리스트 검증 스크립트
- 체크 1: DB에 image_hash 컬럼 + 인덱스 추가
- 체크 2: get_result_by_hash() 함수 구현
- 체크 3: save_result()에 image_hash 파라미터 추가
- 체크 4: 같은 해시로 2번 요청 시 LLM 호출 없이 캐시 결과 반환 확인
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
TEST_HASH = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

# ==================== 체크 4-1: 첫 번째 요청 (캐시 미스 → LLM 호출) ====================
print("=" * 60)
print("[체크 4-1] 첫 번째 요청 (캐시 미스 → LLM 호출)")
req_data = {
    "ocr_text": "[기프티콘] 투썸플레이스 아이스 아메리카노\n유효기간: 2026.12.31\n교환처: 투썸플레이스 전 매장",
    "type": "SCHEDULE",
    "masked_tokens": [],
    "image_hash": TEST_HASH
}

start = time.time()
status1, body1 = post_json("/analyze/v2", req_data)
elapsed1 = time.time() - start

if status1 == 200:
    print(f"  status: {status1}")
    print(f"  type: {body1['type']}, id: {body1['id']}")
    print(f"  fields keys: {list(body1.get('fields', {}).keys())}")
    print(f"  소요 시간: {elapsed1:.2f}초 (LLM 호출 포함)")
    print(f"  ✅ 첫 요청 성공!")
    results.append(("체크 4-1: 첫 요청 (캐시 미스)", True))
else:
    print(f"  ❌ 실패! status={status1}")
    results.append(("체크 4-1: 첫 요청 (캐시 미스)", False))

# ==================== 체크 4-2: 두 번째 요청 (같은 해시 → 캐시 히트) ====================
print()
print("[체크 4-2] 두 번째 요청 (같은 해시 → 캐시 히트, LLM 호출 없음)")

start = time.time()
status2, body2 = post_json("/analyze/v2", req_data)
elapsed2 = time.time() - start

if status2 == 200:
    print(f"  status: {status2}")
    print(f"  type: {body2['type']}, id: {body2['id']}")
    print(f"  소요 시간: {elapsed2:.2f}초 (캐시 히트라면 1초 미만이어야 함)")

    # 캐시 히트 판별: 두 번째 요청이 첫 번째보다 훨씬 빨라야 하고, 같은 id를 반환해야 함
    is_cache_hit = elapsed2 < 2.0  # 캐시면 1초 미만
    same_id = body1.get("id") == body2.get("id")
    same_type = body1.get("type") == body2.get("type")

    if is_cache_hit and same_id and same_type:
        print(f"  ✅ 캐시 히트 확인! (id 동일: {same_id}, 시간 단축: {elapsed1:.2f}s → {elapsed2:.2f}s)")
        results.append(("체크 4-2: 캐시 히트 (LLM 호출 없음)", True))
    else:
        print(f"  ⚠️ 캐시 미스 가능성: same_id={same_id}, fast={is_cache_hit}")
        if not is_cache_hit:
            print(f"     → 두 번째 요청이 {elapsed2:.2f}초 소요 (2초 이상이면 LLM 호출된 것)")
        if not same_id:
            print(f"     → id 불일치: 첫 번째={body1.get('id')}, 두 번째={body2.get('id')}")
        results.append(("체크 4-2: 캐시 히트 (LLM 호출 없음)", False))
else:
    print(f"  ❌ 실패! status={status2}")
    results.append(("체크 4-2: 캐시 히트 (LLM 호출 없음)", False))

# ==================== 체크 4-3: 다른 해시로 요청 (캐시 미스 확인) ====================
print()
print("[체크 4-3] 다른 해시로 요청 (캐시 미스 → 새로운 LLM 호출)")
diff_req = {
    "ocr_text": "을지다락 ★4.5\n서울 중구 을지로 115\n영업시간 11:00-22:00",
    "type": "PLACE",
    "masked_tokens": [],
    "image_hash": "different_hash_abc123"
}

start = time.time()
status3, body3 = post_json("/analyze/v2", diff_req)
elapsed3 = time.time() - start

if status3 == 200 and body3.get("id") != body1.get("id"):
    print(f"  status: {status3}, 새로운 id: {body3['id']}")
    print(f"  소요 시간: {elapsed3:.2f}초 (LLM 호출 포함)")
    print(f"  ✅ 다른 해시는 캐시 미스 정상!")
    results.append(("체크 4-3: 다른 해시 → 캐시 미스", True))
else:
    print(f"  ❌ 실패! status={status3}")
    results.append(("체크 4-3: 다른 해시 → 캐시 미스", False))

# ==================== 체크 4-4: 해시 없이 요청 (캐시 건너뛰기) ====================
print()
print("[체크 4-4] 해시 없이 요청 (캐시 로직 건너뛰기)")
no_hash_req = {
    "ocr_text": "[기프티콘] 투썸플레이스 아이스 아메리카노\n유효기간: 2026.12.31",
    "type": "SCHEDULE",
    "masked_tokens": []
}

start = time.time()
status4, body4 = post_json("/analyze/v2", no_hash_req)
elapsed4 = time.time() - start

if status4 == 200 and body4.get("id") != body1.get("id"):
    print(f"  status: {status4}, 새로운 id: {body4['id']}")
    print(f"  소요 시간: {elapsed4:.2f}초")
    print(f"  ✅ 해시 없이도 정상 동작!")
    results.append(("체크 4-4: 해시 없이 → 정상 동작", True))
else:
    print(f"  ❌ 실패! status={status4}")
    results.append(("체크 4-4: 해시 없이 → 정상 동작", False))

# ==================== 결과 요약 ====================
print()
print("=" * 60)
passed = sum(1 for _, ok in results if ok)
total_tests = len(results)
print(f"Day 23 체크리스트 결과: {passed}/{total_tests} 통과")
for name, ok in results:
    icon = "✅" if ok else "❌"
    print(f"  {icon} {name}")
print("=" * 60)

if passed < total_tests:
    sys.exit(1)
