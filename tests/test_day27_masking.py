"""
Day 27 체크리스트 검증 스크립트
- 체크 1: _detect_token_type() 동작 및 masked_info 생성 로직 검증
- 체크 2: 마스킹 토큰 포함 요청 시 masked_info 정상 반환 확인
- 체크 3: 마스킹 토큰 없을 시 빈 리스트 반환 확인
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
print("[체크 1+2] 마스킹 토큰 포함 요청 (카드, 바코드, 전화번호)")
# 텍스트에 마스킹된 토큰이 있는 척하며, masked_tokens 리스트에 원본을 보냄
req_with_masking = {
    "ocr_text": "결제카드: 1234-****-****-****\n전화번호: 010-****-5678\n바코드: ************",
    "type": "MEMO",
    "masked_tokens": [
        "1234-1234-1234-1234",  # CARD
        "010-1234-5678",        # PHONE
        "1234567890123"         # BARCODE
    ],
    "image_hash": f"masking_{time.time()}"
}

s1, b1 = post_json("/analyze/v2", req_with_masking)
if s1 == 200:
    masked_info = b1.get("masked_info", [])
    print(f"  반환된 masked_info 수: {len(masked_info)}")
    
    types_found = {info.get("type") for info in masked_info}
    print(f"  감지된 타입들: {types_found}")
    
    # CARD, PHONE, BARCODE가 정상적으로 판별되었는지 확인
    if len(masked_info) == 3 and {"CARD", "PHONE", "BARCODE"}.issubset(types_found):
        print("  ✅ 마스킹 정보 구조화 성공!")
        results.append(("체크 2: 마스킹 포함 응답 검증", True))
    else:
        print("  ❌ 실패! 판별 로직 오류")
        results.append(("체크 2: 마스킹 포함 응답 검증", False))
else:
    print(f"  ❌ 에러: {s1}")
    results.append(("체크 2: 마스킹 포함 응답 검증", False))


print("\n[체크 3] 마스킹 토큰 없는 요청 (빈 배열 반환 확인)")
req_no_masking = {
    "ocr_text": "단순한 메모 텍스트입니다.",
    "type": "MEMO",
    "masked_tokens": [],
    "image_hash": f"no_masking_{time.time()}"
}
s2, b2 = post_json("/analyze/v2", req_no_masking)
if s2 == 200:
    masked_info = b2.get("masked_info")
    print(f"  반환된 masked_info: {masked_info}")
    
    if isinstance(masked_info, list) and len(masked_info) == 0:
        print("  ✅ 마스킹 없는 요청도 정상 처리 성공!")
        results.append(("체크 3: 마스킹 없는 응답 검증", True))
    else:
        print("  ❌ 실패! 빈 배열이 아님")
        results.append(("체크 3: 마스킹 없는 응답 검증", False))
else:
    print(f"  ❌ 에러: {s2}")
    results.append(("체크 3: 마스킹 없는 응답 검증", False))

# ==================== 결과 요약 ====================
print("\n" + "=" * 60)
passed = sum(1 for _, ok in results if ok)
total_tests = len(results)
print(f"Day 27 체크리스트 결과: {passed}/{total_tests} 통과")
for name, ok in results:
    icon = "✅" if ok else "❌"
    print(f"  {icon} {name}")
print("=" * 60)

if passed < total_tests:
    sys.exit(1)
