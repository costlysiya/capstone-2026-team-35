from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from openai import OpenAI
from dotenv import load_dotenv
import json

# Day 5: DB 모듈에서 필요한 함수 불러오기
from database import init_db, save_result, get_all_results, update_status

load_dotenv()
client = OpenAI()
app = FastAPI(title="소생 앱 API")


# --- 요청/응답 데이터 형식 정의 ---

class AnalyzeRequest(BaseModel):
    """앱에서 보내는 요청"""
    ocr_text: str                
    masked_tokens: list[str] = []  

class AnalyzeResponse(BaseModel):
    """서버가 돌려주는 응답"""
    type: str          
    confidence: float  
    fields: dict       
    missing_fields: list[str] = []  


# --- 시스템 프롬프트 (LLM에게 주는 역할 지시) ---

SYSTEM_PROMPT = """당신은 스크린샷 OCR 텍스트를 분석하는 AI입니다.

## 분류 규칙
- SCHEDULE: 기프티콘 유효기간, OTT 구독 만료, 일반 일정
- PLACE: 맛집, 카페, 장소 정보
- WISHLIST: 쇼핑, 상품, 가격 정보
- MEMO: 뉴스, 공지, 전자책 등 텍스트 정보

## 출력 형식 (JSON)
{
  "type": "SCHEDULE | PLACE | WISHLIST | MEMO",
  "confidence": 0.00~1.00,
  "fields": { ... },
  "missing_fields": ["누락된 필수 필드명"]
}

## 타입별 필수 필드
- SCHEDULE: title, expires_at(YYYY-MM-DD) 또는 start_at
- PLACE: name 또는 region
- WISHLIST: product_name, price_amount(숫자)
- MEMO: body (title은 자동 생성 가능)
"""


# --- API 엔드포인트 ---

# Day 5: 서버가 시작될 때 데이터베이스 테이블 초기화
@app.on_event("startup")
def startup():
    init_db()


@app.get("/")
def health_check():
    return {"status": "running", "service": "소생 앱 API"}


@app.post("/analyze", response_model=AnalyzeResponse)
def analyze_screenshot(request: AnalyzeRequest):
    """
    앱에서 OCR 텍스트를 받아 → LLM으로 분석 → 구조화된 결과 반환 및 DB 저장
    """
    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": request.ocr_text}
            ],
            response_format={"type": "json_object"},
            temperature=0.1  
        )

        result = json.loads(response.choices[0].message.content)

        # Day 5: 분석 결과를 반환하기 직전에 DB에 저장하는 로직 추가
        row_id = save_result(
            type=result.get("type", "MEMO"),
            confidence=result.get("confidence", 0.0),
            fields=json.dumps(result.get("fields", {}), ensure_ascii=False)
        )

        return AnalyzeResponse(
            type=result.get("type", "MEMO"),
            confidence=result.get("confidence", 0.0),
            fields=result.get("fields", {}),
            missing_fields=result.get("missing_fields", [])
        )

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"분석 실패: {str(e)}")


# --- Day 5: 새로 추가된 DB 관련 엔드포인트 ---

@app.get("/results")
def list_results():
    """저장된 모든 분석 결과 목록 조회"""
    return get_all_results()

@app.post("/results/{id}/confirm")
def confirm_result(id: int):
    """특정 분석 결과를 사용자가 승인(CONFIRMED) 상태로 변경"""
    update_status(id, "CONFIRMED")
    return {"message": f"결과 #{id}이(가) 승인되었습니다"}