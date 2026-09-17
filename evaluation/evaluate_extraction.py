"""
소생 앱 - 정보 추출(Extraction) 품질 평가 스크립트
==============================================
카테고리별 50개씩, 총 200개 샘플을 대상으로
(A) 순수 OCR 텍스트 기반 Regex 추출 vs (B) OCR + LLM(GPT-4o-mini) 추출 비교.
정답지(Ground Truth)는 GPT-4o가 생성.
"""

import pandas as pd
import asyncio
import json
import re
import time
from openai import AsyncOpenAI
from dotenv import load_dotenv

load_dotenv()
client = AsyncOpenAI()

CATEGORY_NAMES = {0: 'SCHEDULE', 1: 'PLACE', 2: 'WISHLIST', 3: 'MEMO'}

# ──────────────────────────────────────────────
# 1. Baseline: 온디바이스 Regex 추출
# ──────────────────────────────────────────────
def extract_regex(text):
    """정규표현식으로 날짜, 가격, 장소를 추출 (온디바이스 시뮬레이션)"""
    # 날짜 패턴
    date_patterns = [
        r'(\d{4}[년\.\-/]\s*\d{1,2}[월\.\-/]\s*\d{1,2}[일]?)',  # 2026년6월24일, 2026.06.28
        r'(\d{1,2}[월\.]\s*\d{1,2}[일]?\s*[\(（][월화수목금토일]\s*[\)）])',  # 6월24일(화)
    ]
    dates = []
    for p in date_patterns:
        dates.extend(re.findall(p, text))
    
    # 가격 패턴
    price_patterns = [
        r'(\d{1,3}(?:,\d{3})+)\s*원',           # 309,365원
        r'[₩￦]\s*(\d{1,3}(?:,\d{3})+)',          # ₩10,000
        r'(\d{1,3}(?:,\d{3})+)\s*(?:KRW|krw)',   # 10,000 KRW
        r'(\d+(?:\.\d{2})?)\s*(?:EUR|USD|JPY|¥|€|\$)', # 14.00 EUR
        r'(\d{1,3}(?:,\d{3})+)',                  # 일반 콤마 숫자
    ]
    prices = []
    for p in price_patterns:
        prices.extend(re.findall(p, text))
    
    # 장소 패턴 (키워드 기반)
    place_patterns = [
        r'(?:장소|교환처|위치|가게명|호텔|숙소|매장)\s*[:：]\s*([^\n,]+)',
        r'(?:at|@)\s+([A-Za-z\u3040-\u309f\u30a0-\u30ff\uac00-\ud7a3][^\n,]{2,30})',
    ]
    places = []
    for p in place_patterns:
        places.extend(re.findall(p, text))
    
    return {
        "dates": dates[:3],          # 최대 3개
        "prices": prices[:3],
        "places": places[:2],
    }

# ──────────────────────────────────────────────
# 2. LLM 추출 (앱 서버와 동일 프롬프트)
# ──────────────────────────────────────────────
SYSTEM_PROMPTS = {
    'SCHEDULE': """OCR 텍스트에서 일정/예약/티켓 정보를 추출하세요.
반드시 다음 JSON 형식으로 응답: {"title":"...", "start_at":"YYYY-MM-DD 또는 null", "end_at":"YYYY-MM-DD 또는 null", "expires_at":"YYYY-MM-DD 또는 null", "price":"금액 또는 null", "place":"장소명 또는 null", "content":"기타 주요 내용 요약"}
OCR 오인식은 교정하되 임의로 지어내지 말 것. 취소마감일시는 날짜 필드에 넣지 말 것.""",
    
    'PLACE': """OCR 텍스트에서 장소/맛집/카페 정보를 추출하세요.
반드시 다음 JSON 형식으로 응답: {"name":"상호명", "region":"지역/주소", "rating":"평점 또는 null", "category":"카페/식당/관광지 등", "price":"가격대 또는 null"}
OCR 오인식은 교정하되 임의로 지어내지 말 것.""",
    
    'WISHLIST': """OCR 텍스트에서 상품/쇼핑 정보를 추출하세요.
반드시 다음 JSON 형식으로 응답: {"product_name":"상품명", "price":"가격", "brand":"브랜드 또는 null", "store":"판매처 또는 null"}
OCR 오인식은 교정하되 임의로 지어내지 말 것.""",
    
    'MEMO': """OCR 텍스트에서 핵심 메모 정보를 추출하세요.
반드시 다음 JSON 형식으로 응답: {"title":"제목 또는 핵심 요약", "body":"주요 내용", "date":"언급된 날짜 또는 null", "source":"출처 또는 null"}
OCR 오인식은 교정하되 임의로 지어내지 말 것.""",
}

async def llm_extract(text, category_name):
    prompt_hint = "[시스템 지시: OCR 오인식은 교정하되 임의로 지어내지 말 것. `[ENC:...` 형태 문자열은 원본 그대로 유지할 것.]\n[현재 날짜: 2026년 8월 23일]\n\n"
    start = time.time()
    try:
        resp = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": SYSTEM_PROMPTS[category_name]},
                {"role": "user", "content": prompt_hint + text}
            ],
            response_format={"type": "json_object"},
        )
        latency = time.time() - start
        tokens = resp.usage.total_tokens
        result = json.loads(resp.choices[0].message.content)
        return result, latency, tokens
    except Exception as e:
        return {}, time.time() - start, 0

# ──────────────────────────────────────────────
# 3. Ground Truth 생성 (GPT-4o)
# ──────────────────────────────────────────────
GT_PROMPTS = {
    'SCHEDULE': """다음 OCR 텍스트에서 명시적으로 언급된 정보만 추출하세요.
JSON 형식: {"dates":["텍스트에 있는 모든 날짜"], "prices":["텍스트에 있는 모든 금액"], "places":["텍스트에 있는 모든 장소/상호명"], "title":"일정 제목"}
텍스트에 명시적으로 없는 정보는 빈 배열 또는 null로.""",
    
    'PLACE': """다음 OCR 텍스트에서 명시적으로 언급된 정보만 추출하세요.
JSON 형식: {"name":"상호명/장소명", "region":"지역/주소 또는 null", "rating":"평점 또는 null", "prices":["텍스트에 있는 금액들"]}
텍스트에 명시적으로 없는 정보는 null로.""",
    
    'WISHLIST': """다음 OCR 텍스트에서 명시적으로 언급된 정보만 추출하세요.
JSON 형식: {"product_name":"상품명", "prices":["텍스트에 있는 모든 금액"], "brand":"브랜드 또는 null", "store":"판매처 또는 null"}
텍스트에 명시적으로 없는 정보는 null로.""",
    
    'MEMO': """다음 OCR 텍스트에서 명시적으로 언급된 정보만 추출하세요.
JSON 형식: {"title":"제목/핵심 요약", "dates":["텍스트에 있는 날짜들"], "source":"출처 또는 null"}
텍스트에 명시적으로 없는 정보는 null 또는 빈 배열로.""",
}

async def get_ground_truth(text, category_name):
    try:
        resp = await client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "user", "content": GT_PROMPTS[category_name] + "\n\nOCR 텍스트:\n" + text}
            ],
            response_format={"type": "json_object"},
        )
        return json.loads(resp.choices[0].message.content)
    except:
        return {}

# ──────────────────────────────────────────────
# 4. 비교 평가 로직
# ──────────────────────────────────────────────
def normalize(s):
    if s is None: return ""
    return re.sub(r'[^0-9a-zA-Z가-힣]', '', str(s)).lower()

def list_contains_match(pred_list, gt_list):
    """pred_list 중 gt_list의 어떤 항목과 매칭되는 게 있으면 True"""
    if not gt_list: return None  # GT에 해당 정보 없음 → 평가 제외
    for gt in gt_list:
        gt_n = normalize(gt)
        if not gt_n: continue
        for pred in pred_list:
            pred_n = normalize(pred)
            if not pred_n: continue
            if pred_n in gt_n or gt_n in pred_n:
                return True
    return False

def scalar_match(pred, gt):
    if gt is None or gt == "": return None
    if pred is None or pred == "": return False
    return normalize(pred) in normalize(gt) or normalize(gt) in normalize(pred)

async def evaluate_one(idx, text, label):
    cat = CATEGORY_NAMES[label]
    
    # Ground Truth
    gt = await get_ground_truth(text, cat)
    
    # Regex (온디바이스)
    t0 = time.time()
    regex_result = extract_regex(text)
    regex_latency = time.time() - t0
    
    # LLM
    llm_result, llm_latency, llm_tokens = await llm_extract(text, cat)
    
    # 평가: 카테고리별로 다른 필드 비교
    eval_result = {
        "idx": idx, "category": cat,
        "regex_latency_ms": regex_latency * 1000,
        "llm_latency_s": llm_latency,
        "llm_tokens": llm_tokens,
    }
    
    if cat == 'SCHEDULE':
        gt_dates = gt.get('dates', []) or []
        gt_prices = gt.get('prices', []) or []
        gt_places = gt.get('places', []) or []
        
        # Regex vs GT
        eval_result['regex_date'] = list_contains_match(regex_result['dates'], gt_dates)
        eval_result['regex_price'] = list_contains_match(regex_result['prices'], gt_prices)
        eval_result['regex_place'] = list_contains_match(regex_result['places'], gt_places)
        
        # LLM vs GT
        llm_dates = [v for k in ['start_at','end_at','expires_at'] if (v := llm_result.get(k))]
        llm_prices = [llm_result.get('price')] if llm_result.get('price') else []
        llm_places = [llm_result.get('place')] if llm_result.get('place') else []
        eval_result['llm_date'] = list_contains_match(llm_dates, gt_dates)
        eval_result['llm_price'] = list_contains_match(llm_prices, gt_prices)
        eval_result['llm_place'] = list_contains_match(llm_places, gt_places)
        
    elif cat == 'PLACE':
        gt_name = gt.get('name')
        gt_region = gt.get('region')
        gt_rating = gt.get('rating')
        
        eval_result['regex_place'] = list_contains_match(regex_result['places'], [gt_name] if gt_name else [])
        eval_result['llm_place'] = scalar_match(llm_result.get('name'), gt_name)
        eval_result['llm_region'] = scalar_match(llm_result.get('region'), gt_region)
        eval_result['llm_rating'] = scalar_match(str(llm_result.get('rating','')), str(gt_rating) if gt_rating else None)
        eval_result['regex_price'] = list_contains_match(regex_result['prices'], gt.get('prices', []) or [])
        llm_p = [llm_result.get('price')] if llm_result.get('price') else []
        eval_result['llm_price'] = list_contains_match(llm_p, gt.get('prices', []) or [])
        
    elif cat == 'WISHLIST':
        gt_name = gt.get('product_name')
        gt_prices = gt.get('prices', []) or []
        gt_brand = gt.get('brand')
        
        eval_result['regex_price'] = list_contains_match(regex_result['prices'], gt_prices)
        llm_p = [llm_result.get('price')] if llm_result.get('price') else []
        eval_result['llm_price'] = list_contains_match(llm_p, gt_prices)
        eval_result['llm_product'] = scalar_match(llm_result.get('product_name'), gt_name)
        eval_result['llm_brand'] = scalar_match(llm_result.get('brand'), gt_brand)
        
    elif cat == 'MEMO':
        gt_dates = gt.get('dates', []) or []
        gt_title = gt.get('title')
        
        eval_result['regex_date'] = list_contains_match(regex_result['dates'], gt_dates)
        llm_dates = [llm_result.get('date')] if llm_result.get('date') else []
        eval_result['llm_date'] = list_contains_match(llm_dates, gt_dates)
        eval_result['llm_title'] = scalar_match(llm_result.get('title'), gt_title)
    
    return eval_result

async def main():
    df = pd.read_csv('dataset.csv')
    df = df[df['extracted_text'].notna() & (df['extracted_text'].str.len() > 50)]
    
    # 카테고리별 50개 샘플링
    samples = []
    for label_idx in range(4):
        sub = df[df['label'] == label_idx]
        n = min(50, len(sub))
        samples.append(sub.sample(n=n, random_state=42))
        print(f"  {CATEGORY_NAMES[label_idx]}: {n}개 샘플 추출")
    
    sample_df = pd.concat(samples)
    total = len(sample_df)
    print(f"\n총 {total}개 샘플로 평가 시작...\n")
    
    # 동시 실행 (배치로 나눠서 rate limit 방지)
    all_results = []
    batch_size = 10
    rows = list(sample_df.iterrows())
    
    for i in range(0, len(rows), batch_size):
        batch = rows[i:i+batch_size]
        tasks = [evaluate_one(idx, row['extracted_text'], row['label']) for idx, row in batch]
        results = await asyncio.gather(*tasks)
        all_results.extend(results)
        print(f"  진행: {len(all_results)}/{total}")
    
    # ──────────────────────────────────────────
    # 결과 집계
    # ──────────────────────────────────────────
    def calc_acc(results, key):
        valid = [r for r in results if r.get(key) is not None]
        if not valid: return 0, 0
        correct = sum(1 for r in valid if r[key] == True)
        return correct, len(valid)
    
    print("\n" + "=" * 70)
    print("정보 추출(Extraction) 품질 평가 결과")
    print("=" * 70)
    
    # 카테고리별 결과
    for cat_idx in range(4):
        cat = CATEGORY_NAMES[cat_idx]
        cat_results = [r for r in all_results if r['category'] == cat]
        n = len(cat_results)
        
        avg_regex_ms = sum(r['regex_latency_ms'] for r in cat_results) / n
        avg_llm_s = sum(r['llm_latency_s'] for r in cat_results) / n
        avg_tokens = sum(r['llm_tokens'] for r in cat_results) / n
        
        print(f"\n{'─'*70}")
        print(f"[{cat}] (N={n})")
        print(f"  온디바이스(Regex) 평균 처리시간: {avg_regex_ms:.3f} ms")
        print(f"  LLM(GPT-4o-mini) 평균 처리시간: {avg_llm_s:.2f} s")
        print(f"  LLM 평균 토큰 사용량: {avg_tokens:.0f} tokens/req")
        
        if cat == 'SCHEDULE':
            rd, rdt = calc_acc(cat_results, 'regex_date')
            rp, rpt = calc_acc(cat_results, 'regex_price')
            rpl, rplt = calc_acc(cat_results, 'regex_place')
            ld, ldt = calc_acc(cat_results, 'llm_date')
            lp, lpt = calc_acc(cat_results, 'llm_price')
            lpl, lplt = calc_acc(cat_results, 'llm_place')
            print(f"  날짜: Regex {rd}/{rdt} ({rd/rdt*100:.1f}%) → LLM {ld}/{ldt} ({ld/ldt*100:.1f}%)" if rdt and ldt else "")
            print(f"  가격: Regex {rp}/{rpt} ({rp/rpt*100:.1f}%) → LLM {lp}/{lpt} ({lp/lpt*100:.1f}%)" if rpt and lpt else "")
            print(f"  장소: Regex {rpl}/{rplt} ({rpl/rplt*100:.1f}%) → LLM {lpl}/{lplt} ({lpl/lplt*100:.1f}%)" if rplt and lplt else "")
            
        elif cat == 'PLACE':
            rpl, rplt = calc_acc(cat_results, 'regex_place')
            lpl, lplt = calc_acc(cat_results, 'llm_place')
            llr, llrt = calc_acc(cat_results, 'llm_region')
            llra, llrat = calc_acc(cat_results, 'llm_rating')
            rp, rpt = calc_acc(cat_results, 'regex_price')
            lp, lpt = calc_acc(cat_results, 'llm_price')
            print(f"  상호명: Regex {rpl}/{rplt} ({rpl/rplt*100:.1f}%) → LLM {lpl}/{lplt} ({lpl/lplt*100:.1f}%)" if rplt and lplt else "")
            print(f"  지역: LLM {llr}/{llrt} ({llr/llrt*100:.1f}%)" if llrt else "")
            print(f"  평점: LLM {llra}/{llrat} ({llra/llrat*100:.1f}%)" if llrat else "")
            print(f"  가격: Regex {rp}/{rpt} ({rp/rpt*100:.1f}%) → LLM {lp}/{lpt} ({lp/lpt*100:.1f}%)" if rpt and lpt else "")
            
        elif cat == 'WISHLIST':
            rp, rpt = calc_acc(cat_results, 'regex_price')
            lp, lpt = calc_acc(cat_results, 'llm_price')
            lpn, lpnt = calc_acc(cat_results, 'llm_product')
            lb, lbt = calc_acc(cat_results, 'llm_brand')
            print(f"  가격: Regex {rp}/{rpt} ({rp/rpt*100:.1f}%) → LLM {lp}/{lpt} ({lp/lpt*100:.1f}%)" if rpt and lpt else "")
            print(f"  상품명: LLM {lpn}/{lpnt} ({lpn/lpnt*100:.1f}%)" if lpnt else "")
            print(f"  브랜드: LLM {lb}/{lbt} ({lb/lbt*100:.1f}%)" if lbt else "")
            
        elif cat == 'MEMO':
            rd, rdt = calc_acc(cat_results, 'regex_date')
            ld, ldt = calc_acc(cat_results, 'llm_date')
            lt, ltt = calc_acc(cat_results, 'llm_title')
            print(f"  날짜: Regex {rd}/{rdt} ({rd/rdt*100:.1f}%) → LLM {ld}/{ldt} ({ld/ldt*100:.1f}%)" if rdt and ldt else "")
            print(f"  제목 추출: LLM {lt}/{ltt} ({lt/ltt*100:.1f}%)" if ltt else "")
    
    # 전체 요약
    all_regex_ms = sum(r['regex_latency_ms'] for r in all_results) / total
    all_llm_s = sum(r['llm_latency_s'] for r in all_results) / total
    all_tokens = sum(r['llm_tokens'] for r in all_results) / total
    total_tokens = sum(r['llm_tokens'] for r in all_results)
    
    # GPT-4o-mini pricing: $0.15/1M input, $0.60/1M output
    est_cost = total_tokens * 0.60 / 1_000_000  # rough average
    
    print(f"\n{'='*70}")
    print("전체 요약 (N={})".format(total))
    print(f"  온디바이스(Regex) 평균 처리시간: {all_regex_ms:.3f} ms")
    print(f"  LLM(GPT-4o-mini) 평균 처리시간: {all_llm_s:.2f} s")
    print(f"  LLM 평균 토큰: {all_tokens:.0f} tokens/req")
    print(f"  LLM 총 사용 토큰: {total_tokens:,} tokens")
    print(f"  LLM 예상 총 비용: ${est_cost:.4f} (약 {est_cost*1350:.0f}원)")
    print("=" * 70)
    
    # JSON 저장
    with open('evaluation_results_v2.json', 'w', encoding='utf-8') as f:
        json.dump(all_results, f, ensure_ascii=False, indent=2, default=str)
    print("\n상세 결과 저장: evaluation_results_v2.json")

if __name__ == "__main__":
    asyncio.run(main())
