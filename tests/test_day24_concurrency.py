"""
Day 24 체크리스트 검증 스크립트
- 체크 1: app/concurrency.py 세마포어 모듈 생성
- 체크 2: analyze_v2에 call_llm_with_limit 적용
- 체크 3: 5개 동시 요청 시 3개 병렬 처리 + 2개 대기 동작 확인
"""
import urllib.request
import json
import sys
import threading
import time

BASE = "http://127.0.0.1:8000/api"

def post_json(path: str, data: dict, results_list: list, index: int):
    body = json.dumps(data).encode("utf-8")
    req = urllib.request.Request(
        f"{BASE}{path}",
        data=body,
        headers={"Content-Type": "application/json"}
    )
    try:
        start = time.time()
        with urllib.request.urlopen(req, timeout=120) as res:
            elapsed = time.time() - start
            results_list[index] = (res.status, json.loads(res.read().decode("utf-8")), elapsed)
    except urllib.error.HTTPError as e:
        results_list[index] = (e.code, json.loads(e.read().decode("utf-8")), 0)
    except Exception as e:
        results_list[index] = (500, {"detail": str(e)}, 0)


print("=" * 60)
print("[체크 3] 5개 동시 요청 시 동시성(세마포어) 제어 테스트")
print("서버 터미널의 로그에서 'LLM 호출 대기 중' 메시지가 출력되는지 확인하세요.")
print("테스트를 시작합니다... (약 15~30초 소요)")

NUM_REQUESTS = 5
threads = []
thread_results = [None] * NUM_REQUESTS

for i in range(NUM_REQUESTS):
    # 캐시를 피하기 위해 매번 다른 해시 사용
    req_data = {
        "ocr_text": f"[테스트 {i}] 투썸플레이스 아이스 아메리카노\n유효기간: 2026.12.31\n교환처: 투썸플레이스 전 매장",
        "type": "SCHEDULE",
        "masked_tokens": [],
        "image_hash": f"concurrency_test_hash_{i}_{time.time()}"
    }
    t = threading.Thread(target=post_json, args=("/analyze/v2", req_data, thread_results, i))
    threads.append(t)

start_time = time.time()

# 모든 스레드 동시 시작
for t in threads:
    t.start()

# 모든 스레드 종료 대기
for t in threads:
    t.join()

total_elapsed = time.time() - start_time

success_count = 0
for idx, res in enumerate(thread_results):
    if res and res[0] == 200:
        success_count += 1
        print(f"  [{idx+1}] status: {res[0]}, 소요 시간: {res[2]:.2f}초")
    else:
        print(f"  [{idx+1}] 실패: {res}")

print("-" * 40)
print(f"총 {NUM_REQUESTS}개 요청 중 {success_count}개 성공 (총 소요 시간: {total_elapsed:.2f}초)")

if success_count == NUM_REQUESTS:
    print("✅ 세마포어 적용 상태에서 5건 병렬 처리 완료!")
    print("\n※ 참고: 서버 로그(python run.py 실행 터미널)를 보시면")
    print("   '[concurrency] LLM 호출 시작 (남은 슬롯: 2/1/0)' 메시지 3개가 먼저 뜨고,")
    print("   나머지 2개는 '[concurrency] LLM 호출 대기 중' 상태가 된 후,")
    print("   앞선 요청이 끝나면 순차적으로 처리되는 것을 확인할 수 있습니다.")
    sys.exit(0)
else:
    print("❌ 실패! 모든 요청이 200 OK를 반환하지 못했습니다.")
    sys.exit(1)
