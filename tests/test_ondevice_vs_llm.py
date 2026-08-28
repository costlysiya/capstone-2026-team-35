"""
=============================================================
  온디바이스(OCR 원문 그대로) vs LLM(GPT 분석) 정보 추출 품질 비교 테스트
  
  목적: 캡스톤 중간보고서 자문 피드백 2번 항목 대응
  - 비교군 1: 온디바이스 (OCR 텍스트에서 정규식으로 직접 추출)
  - 비교군 2: LLM (GPT-4o-mini 기반 구조화 추출)
  - 측정 항목: 추출 정확도(날짜, 가격, 장소명 등), 처리 소요 시간
=============================================================
"""
import json
import time
import re
import sys
import os

# Windows 콘솔 한글/이모지 깨짐 방지
sys.stdout.reconfigure(encoding='utf-8')

# 프로젝트 루트를 PYTHONPATH에 추가
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.llm_client import call_llm
from app.prompts import CLASSIFY_PROMPT, get_type_prompt

# ============================================================
# 1. 테스트 데이터 셋 (15개)
#    각 항목에 OCR 텍스트 + 정답(ground_truth) + 카테고리를 정의
# ============================================================

TEST_DATASET = [
    # --- SCHEDULE (일정/기프티콘) ---
    {
        "id": 1,
        "category": "SCHEDULE",
        "description": "스타벅스 기프티콘",
        "ocr_text": "[스타벅스] 아이스 카페 아메리카노 T\n교환처: 스타벅스 전 매장\n유효기간: 2026년 12월 31일까지\n바코드: 1234-5678-9012",
        "ground_truth": {
            "title": "아이스 카페 아메리카노 T",
            "expires_at": "2026-12-31",
            "exchange_place": "스타벅스"
        }
    },
    {
        "id": 2,
        "category": "SCHEDULE",
        "description": "카카오톡 약속 대화",
        "ocr_text": "김민수: 이번 토요일 저녁 7시에 강남역에서 보자\n박지영: ㅇㅇ 좋아! 강남역 11번 출구 앞에서 만나자\n김민수: 그래 7시에 거기서",
        "ground_truth": {
            "title": "약속",
            "start_at": "토요일",
            "start_time": "19:00",
            "participants": ["김민수", "박지영"]
        }
    },
    {
        "id": 3,
        "category": "SCHEDULE",
        "description": "넷플릭스 구독 결제",
        "ocr_text": "넷플릭스 프리미엄\n다음 결제일: 2026.09.15\n월 17,000원\n결제수단: 신한카드 ****1234",
        "ground_truth": {
            "title": "넷플릭스 프리미엄",
            "expires_at": "2026-09-15",
            "sub_type": "SUBSCRIPTION"
        }
    },
    {
        "id": 4,
        "category": "SCHEDULE",
        "description": "KTX 기차표",
        "ocr_text": "KTX 113\n서울 → 부산\n2026년 08월 25일 (월)\n출발 14:00 도착 16:30\n일반실 / 1호차 7A\n운임 59,800원",
        "ground_truth": {
            "title": "KTX 113 서울→부산",
            "start_at": "2026-08-25",
            "start_time": "14:00",
            "sub_type": "TICKET"
        }
    },
    {
        "id": 5,
        "category": "SCHEDULE",
        "description": "시험 마감일",
        "ocr_text": "2026학년도 2학기 기말고사 일정\n과목: 데이터베이스\n시험일: 2026년 12월 18일 (목) 오전 10시\n장소: 공학관 301호",
        "ground_truth": {
            "title": "데이터베이스 기말고사",
            "start_at": "2026-12-18",
            "start_time": "10:00"
        }
    },
    # --- PLACE (장소) ---
    {
        "id": 6,
        "category": "PLACE",
        "description": "맛집 정보",
        "ocr_text": "을지로 골목 맛집\n별난집\n주소: 서울 중구 을지로3가 188-21\n영업시간: 11:30 ~ 22:00 (일요일 휴무)\n평점: 4.5 (리뷰 328개)\n메뉴: 낙지볶음 15,000원 / 곱창전골 30,000원",
        "ground_truth": {
            "name": "별난집",
            "address": "서울 중구 을지로3가 188-21",
            "category": "한식"
        }
    },
    {
        "id": 7,
        "category": "PLACE",
        "description": "카페 추천 대화",
        "ocr_text": "이수현: 혹시 홍대 근처 조용한 카페 알아?\n최유진: 아 연남동에 '어니언' 가봐 빵도 맛있고 분위기 좋아\n이수현: 오 주소 알려줘\n최유진: 서울 마포구 연남동 227-34 거기야",
        "ground_truth": {
            "name": "어니언",
            "region": "마포구 연남동",
            "address": "서울 마포구 연남동 227-34",
            "category": "카페"
        }
    },
    {
        "id": 8,
        "category": "PLACE",
        "description": "네이버 지도 스크린샷",
        "ocr_text": "진로집\n서울 강남구 역삼동 123-4\n한식 > 육류,고기\n영업시간: 16:00 ~ 02:00\n전화: 02-555-1234\n평점 4.3 / 방문자 리뷰 215",
        "ground_truth": {
            "name": "진로집",
            "address": "서울 강남구 역삼동 123-4",
            "category": "한식"
        }
    },
    # --- WISHLIST (위시리스트) ---
    {
        "id": 9,
        "category": "WISHLIST",
        "description": "쿠팡 상품 페이지",
        "ocr_text": "삼성 갤럭시 버즈3 프로\n가격: 359,000원\n할인가: 279,000원 (22% 할인)\n색상: 실버 / 화이트\n배송: 내일 도착 보장\n리뷰 4.7 (1,203개)",
        "ground_truth": {
            "product_name": "삼성 갤럭시 버즈3 프로",
            "price_amount": 279000,
            "original_price": 359000
        }
    },
    {
        "id": 10,
        "category": "WISHLIST",
        "description": "무신사 장바구니",
        "ocr_text": "장바구니\n1. 나이키 에어맥스 90 - 사이즈 270 / 139,000원\n2. 리바이스 501 오리지널 - 사이즈 32 / 89,000원\n합계: 228,000원",
        "ground_truth": {
            "product_name": "나이키 에어맥스 90",
            "price_amount": 139000
        }
    },
    # --- MEMO (메모) ---
    {
        "id": 11,
        "category": "MEMO",
        "description": "요리 레시피",
        "ocr_text": "간장계란밥 레시피\n재료: 밥 1공기, 계란 2개, 간장 2큰술, 참기름 1큰술, 김 약간\n1. 팬에 기름을 두르고 계란 프라이\n2. 밥 위에 계란 올리고 간장, 참기름 뿌려서 비비기\n3. 김 올려서 완성",
        "ground_truth": {
            "title": "간장계란밥",
            "sub_type": "RECIPE"
        }
    },
    {
        "id": 12,
        "category": "MEMO",
        "description": "할 일 체크리스트",
        "ocr_text": "이번 주 할 일\n☑ 논문 초안 작성\n☐ 교수님 미팅 자료 준비\n☐ 알고리즘 과제 제출\n☑ 헬스장 등록\n☐ 도서관 책 반납",
        "ground_truth": {
            "title": "이번 주 할 일",
            "sub_type": "CHECKLIST"
        }
    },
    # --- 추가 엣지 케이스 ---
    {
        "id": 13,
        "category": "SCHEDULE",
        "description": "배달의민족 주문 확인",
        "ocr_text": "주문완료\nBHC 뿌링클+치즈볼\n배달 예상시간: 40~50분 (16:30 도착 예정)\n결제금액: 23,900원\n주소: 서울 관악구 봉천동 123-45",
        "ground_truth": {
            "title": "BHC 뿌링클+치즈볼 배달",
            "start_time": "16:30",
            "sub_type": "DELIVERY"
        }
    },
    {
        "id": 14,
        "category": "PLACE",
        "description": "여행 숙소 정보",
        "ocr_text": "제주 해비치 호텔&리조트\n주소: 제주특별자치도 서귀포시 표선면 민속해안로 537\n체크인: 15:00 / 체크아웃: 11:00\n디럭스 더블룸 1박 320,000원\n평점: 4.6",
        "ground_truth": {
            "name": "제주 해비치 호텔&리조트",
            "address": "제주특별자치도 서귀포시 표선면 민속해안로 537",
            "category": "숙박"
        }
    },
    {
        "id": 15,
        "category": "WISHLIST",
        "description": "당근마켓 중고상품",
        "ocr_text": "아이패드 프로 11인치 4세대 M2칩\n256GB / 스페이스그레이\n애플펜슬 2세대 + 매직키보드 포함\n가격: 850,000원 (정가 대비 40% 할인)\n거래 희망 지역: 서울 강남구",
        "ground_truth": {
            "product_name": "아이패드 프로 11인치 4세대",
            "price_amount": 850000
        }
    }
]


# ============================================================
# 2. 온디바이스 추출기 (정규식 기반 — OCR 텍스트만으로 파싱)
# ============================================================

def extract_ondevice(ocr_text: str) -> dict:
    """
    정규식(Regex)만으로 OCR 텍스트에서 정보를 추출합니다.
    실제 앱의 온디바이스 분류기는 ML Kit 등으로 카테고리를 분류하지만,
    '정보 추출(구조화)' 부분은 정규식 수준으로 시뮬레이션합니다.
    """
    result = {}
    
    # --- 날짜 추출 ---
    date_patterns = [
        r'(\d{4})[년.\-/]\s*(\d{1,2})[월.\-/]\s*(\d{1,2})[일]?',
        r'(\d{2})[.\-/](\d{2})[.\-/](\d{2})',
    ]
    dates_found = []
    for pat in date_patterns:
        for m in re.finditer(pat, ocr_text):
            groups = m.groups()
            if len(groups[0]) == 4:
                dates_found.append(f"{groups[0]}-{int(groups[1]):02d}-{int(groups[2]):02d}")
            else:
                dates_found.append(f"20{groups[0]}-{int(groups[1]):02d}-{int(groups[2]):02d}")
    
    if dates_found:
        if re.search(r'(유효기간|만료|까지|결제일)', ocr_text):
            result["expires_at"] = dates_found[0]
        else:
            result["start_at"] = dates_found[0]
    
    # --- 시간 추출 ---
    time_match = re.search(r'(\d{1,2})\s*[:시]\s*(\d{2})\s*(분)?', ocr_text)
    if time_match:
        h = int(time_match.group(1))
        m = int(time_match.group(2))
        if re.search(r'(오후|저녁|PM)', ocr_text[:time_match.start()]):
            if h < 12:
                h += 12
        result["start_time"] = f"{h:02d}:{m:02d}"
    
    # --- 가격 추출 ---
    price_matches = re.findall(r'([\d,]+)\s*원', ocr_text)
    if price_matches:
        prices = [int(p.replace(',', '')) for p in price_matches]
        result["price_amount"] = min(prices)
    
    # --- 장소/이름 추출 ---
    addr_match = re.search(r'(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)[\s\S]{5,40}?(동|로|길|면)\s*\d*[\-\d]*', ocr_text)
    if addr_match:
        result["address"] = addr_match.group(0).strip()
    
    first_line = ocr_text.strip().split('\n')[0].strip()
    bracket_match = re.search(r'\[(.+?)\]', ocr_text)
    if bracket_match:
        result["title"] = bracket_match.group(1)
    else:
        if len(first_line) <= 30:
            result["title"] = first_line
    
    if result.get("price_amount") and not result.get("title"):
        result["product_name"] = first_line
    
    # --- 참여자 추출 ---
    name_pattern = re.findall(r'^([\uAC00-\uD7AF]{2,4})\s*:', ocr_text, re.MULTILINE)
    if name_pattern:
        result["participants"] = list(set(name_pattern))
    
    # 교환처
    exchange_match = re.search(r'교환처\s*[:：]\s*(.+)', ocr_text)
    if exchange_match:
        result["exchange_place"] = exchange_match.group(1).strip()

    return result


# ============================================================
# 3. LLM 추출기 (서버의 2단계 파이프라인 재현)
# ============================================================

def extract_llm(ocr_text: str) -> dict:
    """서버의 실제 2단계 파이프라인(분류 -> 추출)을 그대로 재현"""
    
    # 1단계: 분류
    classify_result = call_llm(
        system_prompt=CLASSIFY_PROMPT,
        user_text=ocr_text
    )
    detected_type = classify_result.get("type", "MEMO")
    
    # 2단계: 타입별 상세 추출
    extract_result = call_llm(
        system_prompt=get_type_prompt(detected_type),
        user_text=ocr_text
    )
    
    fields = extract_result.get("fields", extract_result)
    
    # fields가 리스트면 첫 번째 항목 사용
    if isinstance(fields, list):
        fields = fields[0] if len(fields) > 0 else {}
    
    if "items" in fields and isinstance(fields["items"], list) and len(fields["items"]) > 0:
        fields = fields["items"][0]
    
    # fields가 여전히 dict가 아니면 빈 dict로
    if not isinstance(fields, dict):
        fields = {}
    
    return {
        "detected_type": detected_type,
        "fields": fields
    }


# ============================================================
# 4. 정확도 평가 함수
# ============================================================

def evaluate_accuracy(extracted: dict, ground_truth: dict) -> dict:
    """추출 결과와 정답을 비교하여 필드별 정확도를 계산"""
    scores = {}
    
    for key, expected in ground_truth.items():
        actual = extracted.get(key)
        
        if actual is None:
            scores[key] = {"match": False, "expected": expected, "actual": None, "reason": "미추출"}
            continue
        
        if isinstance(expected, list):
            if isinstance(actual, list):
                overlap = len(set(str(e).lower() for e in expected) & set(str(a).lower() for a in actual))
                total = len(expected)
                scores[key] = {
                    "match": overlap == total,
                    "partial": f"{overlap}/{total}",
                    "expected": expected,
                    "actual": actual,
                    "reason": "리스트 비교"
                }
            else:
                scores[key] = {"match": False, "expected": expected, "actual": actual, "reason": "타입 불일치"}
            continue
        
        if isinstance(expected, (int, float)):
            try:
                actual_num = float(str(actual).replace(',', ''))
                scores[key] = {
                    "match": abs(actual_num - expected) < 1,
                    "expected": expected,
                    "actual": actual_num,
                    "reason": "숫자 비교"
                }
            except (ValueError, TypeError):
                scores[key] = {"match": False, "expected": expected, "actual": actual, "reason": "숫자 변환 실패"}
            continue
        
        expected_str = str(expected).lower().strip()
        actual_str = str(actual).lower().strip()
        
        exact_match = expected_str == actual_str
        partial_match = expected_str in actual_str or actual_str in expected_str
        
        scores[key] = {
            "match": exact_match or partial_match,
            "expected": expected,
            "actual": actual,
            "reason": "정확일치" if exact_match else ("부분일치" if partial_match else "불일치")
        }
    
    return scores


# ============================================================
# 5. 메인 실행부
# ============================================================

def run_comparison_test():
    print("=" * 80)
    print("  온디바이스(OCR+Regex) vs LLM(GPT) 정보 추출 품질/성능 비교 테스트")
    print("=" * 80)
    print()
    
    results = []
    
    for test in TEST_DATASET:
        print(f"▶ [{test['id']:02d}] {test['description']} ({test['category']})")
        print(f"  OCR: {test['ocr_text'][:60]}...")
        
        # --- 비교군 1: 온디바이스(Regex) ---
        t1 = time.time()
        ondevice_result = extract_ondevice(test["ocr_text"])
        ondevice_time = (time.time() - t1) * 1000
        
        ondevice_scores = evaluate_accuracy(ondevice_result, test["ground_truth"])
        ondevice_correct = sum(1 for s in ondevice_scores.values() if s["match"])
        ondevice_total = len(ondevice_scores)
        
        # --- 비교군 2: LLM(GPT) ---
        t2 = time.time()
        llm_result = extract_llm(test["ocr_text"])
        llm_time = (time.time() - t2) * 1000
        
        llm_scores = evaluate_accuracy(llm_result["fields"], test["ground_truth"])
        llm_correct = sum(1 for s in llm_scores.values() if s["match"])
        llm_total = len(llm_scores)
        
        print(f"  📱 온디바이스: {ondevice_correct}/{ondevice_total} 정확 ({ondevice_time:.1f}ms)")
        print(f"  🤖 LLM(GPT):  {llm_correct}/{llm_total} 정확 ({llm_time:.1f}ms)")
        print()
        
        results.append({
            "id": test["id"],
            "description": test["description"],
            "category": test["category"],
            "ondevice": {
                "correct": ondevice_correct,
                "total": ondevice_total,
                "accuracy": ondevice_correct / ondevice_total if ondevice_total > 0 else 0,
                "time_ms": ondevice_time,
                "scores": ondevice_scores,
                "raw": ondevice_result
            },
            "llm": {
                "correct": llm_correct,
                "total": llm_total,
                "accuracy": llm_correct / llm_total if llm_total > 0 else 0,
                "time_ms": llm_time,
                "detected_type": llm_result["detected_type"],
                "scores": llm_scores,
                "raw": llm_result["fields"]
            }
        })
    
    # ============================================================
    # 6. 결과 요약 테이블 출력
    # ============================================================
    print()
    print("=" * 100)
    print("  📊 최종 결과 요약 테이블")
    print("=" * 100)
    print(f"{'No':>3} | {'설명':<25} | {'카테고리':<10} | {'온디바이스 정확도':>16} | {'LLM 정확도':>12} | {'온디바이스 시간':>14} | {'LLM 시간':>10}")
    print("-" * 100)
    
    total_ondevice_correct = 0
    total_llm_correct = 0
    total_fields = 0
    total_ondevice_time = 0
    total_llm_time = 0
    
    for r in results:
        od = r["ondevice"]
        lm = r["llm"]
        total_ondevice_correct += od["correct"]
        total_llm_correct += lm["correct"]
        total_fields += od["total"]
        total_ondevice_time += od["time_ms"]
        total_llm_time += lm["time_ms"]
        
        print(f"{r['id']:>3} | {r['description']:<25} | {r['category']:<10} | {od['correct']}/{od['total']} ({od['accuracy']*100:5.1f}%) | {lm['correct']}/{lm['total']} ({lm['accuracy']*100:5.1f}%) | {od['time_ms']:>10.1f} ms | {lm['time_ms']:>7.1f} ms")
    
    print("-" * 100)
    od_pct = (total_ondevice_correct / total_fields * 100) if total_fields > 0 else 0
    lm_pct = (total_llm_correct / total_fields * 100) if total_fields > 0 else 0
    print(f"{'합계':>3} | {'':25} | {'':10} | {total_ondevice_correct}/{total_fields} ({od_pct:5.1f}%) | {total_llm_correct}/{total_fields} ({lm_pct:5.1f}%) | {total_ondevice_time:>10.1f} ms | {total_llm_time:>7.1f} ms")
    
    print()
    print("=" * 100)
    print("  📈 카테고리별 비교")
    print("=" * 100)
    
    for cat in ["SCHEDULE", "PLACE", "WISHLIST", "MEMO"]:
        cat_results = [r for r in results if r["category"] == cat]
        if not cat_results:
            continue
        od_c = sum(r["ondevice"]["correct"] for r in cat_results)
        lm_c = sum(r["llm"]["correct"] for r in cat_results)
        tot = sum(r["ondevice"]["total"] for r in cat_results)
        od_t = sum(r["ondevice"]["time_ms"] for r in cat_results)
        lm_t = sum(r["llm"]["time_ms"] for r in cat_results)
        n = len(cat_results)
        
        print(f"  [{cat}] ({n}건)")
        print(f"    온디바이스: {od_c}/{tot} 정확 ({od_c/tot*100:.1f}%) | 평균 {od_t/n:.1f} ms")
        print(f"    LLM(GPT):  {lm_c}/{tot} 정확 ({lm_c/tot*100:.1f}%) | 평균 {lm_t/n:.1f} ms")
        print(f"    속도 차이:  LLM이 {lm_t/max(od_t, 0.001):.0f}배 느림")
        print()
    
    # ============================================================
    # 7. 필드별 상세 비교 (불일치 케이스만)
    # ============================================================
    print("=" * 100)
    print("  🔍 필드별 상세 비교 (불일치 케이스)")
    print("=" * 100)
    
    for r in results:
        has_diff = False
        for field, od_score in r["ondevice"]["scores"].items():
            lm_score = r["llm"]["scores"].get(field, {"match": False, "actual": None})
            if not od_score["match"] or not lm_score.get("match", False):
                if not has_diff:
                    print(f"\n  [{r['id']:02d}] {r['description']}")
                    has_diff = True
                od_icon = "✅" if od_score["match"] else "❌"
                lm_icon = "✅" if lm_score.get("match", False) else "❌"
                print(f"    {field}: 정답={od_score['expected']}")
                print(f"      온디바이스 {od_icon}: {od_score['actual']}")
                print(f"      LLM       {lm_icon}: {lm_score.get('actual', 'N/A')}")
    
    # JSON 결과 저장
    output_path = os.path.join(os.path.dirname(__file__), "comparison_results.json")
    with open(output_path, "w", encoding="utf-8") as f:
        save_data = []
        for r in results:
            save_data.append({
                "id": r["id"],
                "description": r["description"],
                "category": r["category"],
                "ondevice_accuracy": r["ondevice"]["accuracy"],
                "ondevice_time_ms": r["ondevice"]["time_ms"],
                "llm_accuracy": r["llm"]["accuracy"],
                "llm_time_ms": r["llm"]["time_ms"],
                "llm_detected_type": r["llm"]["detected_type"]
            })
        json.dump(save_data, f, ensure_ascii=False, indent=2)
    
    print(f"\n\n💾 상세 결과가 {output_path} 에 저장되었습니다.")
    print("\n테스트 완료!")


if __name__ == "__main__":
    run_comparison_test()
