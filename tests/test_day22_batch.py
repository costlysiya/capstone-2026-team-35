"""
Day 22 Batch 분석 기능 테스트 스크립트
- 체크 1: BatchAnalyzeRequest, BatchAnalyzeResponse 스키마 추가 → import 검증
- 체크 2: POST /api/analyze/batch 엔드포인트 구현 → 2개 항목 배치 테스트
- 체크 3: 20개 초과 요청 시 400 에러 반환 확인
- 체크 4: /docs에서 2~3개 항목 배치 테스트 성공 (스크립트로 대체)
"""
import urllib.request
import json
import sys

BASE = "http://127.0.0.1:8000/api"

def post_json(path: str, data: dict) -> tuple[int, dict]:
    """POST 요청을 보내고 (status_code, body) 반환"""
    body = json.dumps(data).encode("utf-8")
    req = urllib.request.Request(
        f"{BASE}{path}",
        data=body,
        headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            return res.status, json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode("utf-8"))

results = []

# ==================== 체크 3: 20개 초과 요청 시 400 에러 ====================
print("=" * 60)
print("[체크 3] 20개 초과 요청 시 400 에러 반환 확인")
over_limit = {
    "items": [{"ocr_text": f"test item {i}", "masked_tokens": []} for i in range(21)]
}
status, body = post_json("/analyze/batch", over_limit)
if status == 400:
    print(f"  ✅ 통과! status={status}, detail={body.get('detail', '')}")
    results.append(("체크 3: 20개 초과 → 400", True))
else:
    print(f"  ❌ 실패! status={status}")
    results.append(("체크 3: 20개 초과 → 400", False))

# ==================== 체크 2+4: 2개 항목 배치 테스트 ====================
print()
print("[체크 2+4] 2개 항목 배치 분석 테스트")
batch_req = {
    "items": [
        {
            "ocr_text": "[기프티콘] 스타벅스 아이스 아메리카노\n유효기간: 2026.08.15\n교환처: 스타벅스 전 매장",
            "type": "SCHEDULE",
            "masked_tokens": []
        },
        {
            "ocr_text": "을지다락 ★4.5\n서울 중구 을지로 115\n영업시간 11:00-22:00\n한식",
            "type": "PLACE",
            "masked_tokens": []
        }
    ]
}
status, body = post_json("/analyze/batch", batch_req)

if status == 200:
    total = body.get("total", 0)
    success = body.get("success", 0)
    failed = body.get("failed", 0)
    batch_results = body.get("results", [])

    print(f"  total: {total}, success: {success}, failed: {failed}")

    all_ok = total == 2 and success == 2 and failed == 0

    for idx, r in enumerate(batch_results):
        print(f"  [{idx+1}] type={r['type']}, confidence={r['confidence']}, status={r['status']}")
        print(f"      fields keys: {list(r.get('fields', {}).keys())}")

    if all_ok:
        print(f"  ✅ 통과! 2개 항목 모두 성공")
        results.append(("체크 2+4: 2개 배치 분석 성공", True))
    else:
        print(f"  ❌ 실패! total/success/failed 불일치")
        results.append(("체크 2+4: 2개 배치 분석 성공", False))
else:
    print(f"  ❌ 실패! status={status}")
    results.append(("체크 2+4: 2개 배치 분석 성공", False))

# ==================== 빈 배열 요청 테스트 (보너스) ====================
print()
print("[보너스] 빈 배열 요청 시 400 에러 확인")
status, body = post_json("/analyze/batch", {"items": []})
if status in (400, 422):
    print(f"  ✅ 통과! status={status}")
    results.append(("보너스: 빈 배열 → 400", True))
else:
    print(f"  ❌ 실패! status={status}")
    results.append(("보너스: 빈 배열 → 400", False))

# ==================== 결과 요약 ====================
print()
print("=" * 60)
passed = sum(1 for _, ok in results if ok)
total_tests = len(results)
print(f"Day 22 체크리스트 결과: {passed}/{total_tests} 통과")
for name, ok in results:
    icon = "✅" if ok else "❌"
    print(f"  {icon} {name}")
print("=" * 60)

if passed < total_tests:
    sys.exit(1)
