# 📅 오예린 2주차 가이드 — 실전 프로젝트 업그레이드

> **현재 상태**: Day 1~7 온보딩 완료 (FastAPI + OpenAI + SQLite + 검증 레이어)  
> **2주차 목표**: 졸업과제용 실전 코드로 업그레이드 + 팀과 합칠 준비

---

## Day 8 (월) — Git 첫 커밋 + 팀 합류 준비

> [!IMPORTANT]
> 아직 커밋 안 했으니 이걸 제일 먼저! 코드를 잃어버리면 1주일이 날아가요.

### 1단계: Git 초기화 + .gitignore

```powershell
cd C:\your-project-path  # 본인 프로젝트 폴더로 이동

git init
```

`.gitignore` 파일 만들기:

```
# 가상환경
venv/

# 환경변수 (API 키!)
.env

# 데이터베이스
*.db

# Python 캐시
__pycache__/
*.pyc
*.pyo

# IDE
.vscode/
.idea/
```

### 2단계: 첫 커밋

```powershell
git add .
git status          # 올라갈 파일 확인 (.env, venv 빠졌는지 체크!)
git commit -m "feat: 백엔드 초기 세팅 (FastAPI + OpenAI + SQLite + 검증레이어)"
```

### 3단계: 팀 저장소에 연결 (팀장이 만들었다면)

```powershell
# 팀 저장소 주소를 팀장(정채윤)한테 받아서:
git remote add origin https://github.com/팀저장소주소.git

# 브랜치 만들어서 작업하기 (main에 바로 푸시 X)
git checkout -b feature/backend-api
git push -u origin feature/backend-api
```

> [!TIP]
> 팀 저장소가 아직 없으면, 정채윤 팀장한테 "저장소 만들어주세요, 제 코드 푸시할게요"라고 말하세요.

### ✅ Day 8 체크리스트
- [ ] `.gitignore`에 `.env`, `venv/`, `*.db` 가 포함되어 있다
- [ ] 첫 번째 커밋이 완료되었다
- [ ] (팀 저장소가 있다면) 내 브랜치를 푸시했다

---

## Day 9 (화) — 프로젝트 구조 정리

> [!TIP]
> 오늘의 목표: 파일이 많아져도 관리할 수 있는 구조로 바꾸기

현재 코드가 `main.py` 하나에 다 있을 텐데, **역할별로 파일을 분리**해요.

### 목표 폴더 구조

```
soseng-backend/
├── app/
│   ├── __init__.py          ← 빈 파일 (Python 패키지 표시)
│   ├── main.py              ← FastAPI 앱 생성 + 라우터 연결
│   ├── config.py            ← 설정 (API 키, DB 경로 등)
│   ├── database.py          ← DB 관련 (기존 코드 이동)
│   ├── validator.py         ← 검증 로직 (기존 코드 이동)
│   ├── prompts.py           ← LLM 프롬프트 모음 (NEW!)
│   ├── schemas.py           ← 요청/응답 데이터 형식 (NEW!)
│   └── routers/
│       ├── __init__.py
│       ├── analyze.py       ← /analyze 관련 API
│       └── results.py       ← /results 관련 API
├── tests/                   ← 테스트 코드
│   └── test_analyze.py
├── .env
├── .gitignore
├── requirements.txt
└── run.py                   ← 서버 실행 진입점
```

### 핵심 파일들

**`app/config.py`** — 설정을 한 곳에서 관리:

```python
from dotenv import load_dotenv
import os

load_dotenv()

# OpenAI
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_MODEL = "gpt-4o-mini"  # 모델 바꿀 때 여기만 수정

# DB
DB_PATH = "soseng.db"

# LLM 설정
LLM_TEMPERATURE = 0.1  # 낮을수록 일관된 답변
LLM_MAX_TOKENS = 1000
```

**`app/schemas.py`** — 요청/응답 형식 정의:

```python
from pydantic import BaseModel
from enum import Enum

class ScreenshotType(str, Enum):
    """4대 분류 타입"""
    SCHEDULE = "SCHEDULE"
    PLACE = "PLACE"
    WISHLIST = "WISHLIST"
    MEMO = "MEMO"

class AnalyzeRequest(BaseModel):
    """앱 → 서버 요청"""
    ocr_text: str
    masked_tokens: list[str] = []

    class Config:
        json_schema_extra = {
            "example": {
                "ocr_text": "[기프티콘] 스타벅스 아메리카노\n유효기간: 2026.08.15",
                "masked_tokens": ["MASKED_CARD"]
            }
        }

class AnalyzeResponse(BaseModel):
    """서버 → 앱 응답"""
    id: int | None = None
    type: ScreenshotType
    confidence: float
    fields: dict
    missing_fields: list[str] = []
    status: str = "DRAFT"

class ResultConfirmRequest(BaseModel):
    """사용자 승인 요청"""
    edited_fields: dict | None = None  # 수정된 필드 (있으면)
```

**`app/routers/analyze.py`** — 분석 API:

```python
from fastapi import APIRouter, HTTPException
from openai import OpenAI
from app.config import OPENAI_MODEL, LLM_TEMPERATURE
from app.schemas import AnalyzeRequest, AnalyzeResponse
from app.prompts import get_system_prompt
from app.validator import validate_result
from app.database import save_result
import json

router = APIRouter(prefix="/api", tags=["분석"])
client = OpenAI()

@router.post("/analyze", response_model=AnalyzeResponse)
def analyze_screenshot(request: AnalyzeRequest):
    """OCR 텍스트를 받아 분류 + 구조화"""
    try:
        response = client.chat.completions.create(
            model=OPENAI_MODEL,
            messages=[
                {"role": "system", "content": get_system_prompt()},
                {"role": "user", "content": request.ocr_text}
            ],
            response_format={"type": "json_object"},
            temperature=LLM_TEMPERATURE
        )

        result = json.loads(response.choices[0].message.content)
        result = validate_result(result)

        # DB 저장
        row_id = save_result(
            type=result["type"],
            confidence=result.get("confidence", 0),
            fields=json.dumps(result.get("fields", {}), ensure_ascii=False)
        )

        return AnalyzeResponse(
            id=row_id,
            type=result["type"],
            confidence=result.get("confidence", 0),
            fields=result.get("fields", {}),
            missing_fields=result.get("missing_fields", []),
            status=result.get("status", "DRAFT")
        )

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"분석 실패: {str(e)}")
```

**`app/main.py`** — 앱 조립:

```python
from fastapi import FastAPI
from app.database import init_db
from app.routers import analyze, results

app = FastAPI(
    title="소생 앱 API",
    description="스크린샷 정보 추출 및 관리 서버",
    version="0.1.0"
)

@app.on_event("startup")
def startup():
    init_db()

# 라우터 연결
app.include_router(analyze.router)
app.include_router(results.router)

@app.get("/")
def health():
    return {"status": "running", "version": "0.1.0"}
```

**`run.py`** — 실행 파일:

```python
import uvicorn

if __name__ == "__main__":
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
```

```powershell
# 이제 이렇게 실행
python run.py
```

### ✅ Day 9 체크리스트
- [ ] `app/` 폴더 구조로 코드가 분리되었다
- [ ] `python run.py`로 서버가 정상 실행된다
- [ ] `/docs`에서 API가 정상 동작한다
- [ ] 커밋: `refactor: 프로젝트 구조 패키지화`

---

## Day 10 (수) — 타입별 프롬프트 정밀 튜닝 🎯

> [!TIP]
> 오늘의 목표: 4개 타입 각각에 맞는 전문 프롬프트를 만들어서 추출 정확도를 높이기

### 왜 프롬프트를 나누나요?

현재는 하나의 프롬프트로 4개 타입을 다 처리하는데, **타입별로 추출해야 할 필드가 다르기 때문에** 분리하면 정확도가 올라가요.

전략: **2단계 처리**
1. 1차: "이 텍스트가 무슨 타입이야?" (분류)
2. 2차: 해당 타입 전용 프롬프트로 상세 필드 추출

**`app/prompts.py`**:

```python
# ===== 1차: 분류 프롬프트 =====

CLASSIFY_PROMPT = """당신은 스크린샷 OCR 텍스트를 분류하는 AI입니다.

아래 4가지 타입 중 하나로 분류하세요:

1. SCHEDULE - 기프티콘 유효기간, OTT 구독 만료, 약속/일정, 티켓 예매
   키워드 힌트: 유효기간, 만료일, ~까지, 예약, 구독, 결제일, D-
   
2. PLACE - 맛집, 카페, 장소 추천, 위치 정보
   키워드 힌트: 맛집, 카페, 식당, 평점, 리뷰, 영업시간, 주소, ~역, ~동
   
3. WISHLIST - 쇼핑, 상품, 가격 비교
   키워드 힌트: 원, ₩, 할인, 쿠팡, 네이버쇼핑, 장바구니, 사이즈, 배송
   
4. MEMO - 뉴스, 공지, 전자책, 참고용 텍스트
   키워드 힌트: 위 3가지에 해당하지 않는 텍스트 정보

반드시 아래 JSON 형식으로만 응답:
{"type": "SCHEDULE|PLACE|WISHLIST|MEMO", "confidence": 0.0~1.0}
"""

# ===== 2차: 타입별 상세 추출 프롬프트 =====

SCHEDULE_PROMPT = """당신은 일정/기프티콘 정보를 추출하는 AI입니다.

아래 텍스트에서 다음 필드를 추출하세요:

## 필수 필드
- title: 일정/기프티콘 이름 (예: "스타벅스 아메리카노 T")
- expires_at: 만료일 (YYYY-MM-DD 형식). 없으면 null
- start_at: 시작일 (YYYY-MM-DD 형식). 없으면 null

## 선택 필드  
- reminder_days: 알림 추천 일수 (예: [7, 1] → D-7, D-1)
- exchange_place: 교환처/사용처
- description: 기타 정보

## 규칙
- expires_at 또는 start_at 중 하나는 반드시 추출
- 날짜가 "26.08.15" 같은 형식이면 "2026-08-15"로 변환
- "~까지", "유효기간" 뒤의 날짜 → expires_at
- "예약일", "시작일" 뒤의 날짜 → start_at
- 기프티콘이면 reminder_days를 [7, 3, 1]로 자동 추천

JSON 형식으로만 응답:
{"fields": {...}, "missing_fields": [...]}
"""

PLACE_PROMPT = """당신은 장소/맛집 정보를 추출하는 AI입니다.

아래 텍스트에서 다음 필드를 추출하세요:

## 필수 필드 (하나 이상)
- name: 상호명 / 장소명 (예: "을지다락")
- region: 지역 (예: "서울 을지로", "부산 서면")

## 선택 필드
- category: 카테고리 (카페/한식/양식/일식/중식/디저트/술집/기타)
- rating: 평점 (숫자)
- address: 상세 주소
- phone: 전화번호
- hours: 영업시간
- menu_highlights: 추천 메뉴 (리스트)
- source: 출처 (네이버/인스타/카카오맵 등)

## 규칙
- name 또는 region 중 하나는 반드시 추출
- category는 위 목록 중 하나로 정규화

JSON 형식으로만 응답:
{"fields": {...}, "missing_fields": [...]}
"""

WISHLIST_PROMPT = """당신은 쇼핑/상품 정보를 추출하는 AI입니다.

아래 텍스트에서 다음 필드를 추출하세요:

## 필수 필드
- product_name: 상품명 (예: "나이키 에어맥스 90")
- price_amount: 가격 (숫자만, 예: 129000)

## 선택 필드
- price_currency: 통화 (기본값: "KRW")
- original_price: 원래 가격 (할인 전)
- discount_rate: 할인율 (예: "30%")
- seller: 판매처/쇼핑몰 (예: "쿠팡", "무신사")
- category_tag: 카테고리 (의류/전자/식품/뷰티/가구/기타)
- product_url: 상품 URL (있으면)
- size: 사이즈 정보
- color: 색상 정보

## 규칙
- 가격에서 쉼표, "원", "₩" 등을 제거하고 숫자만 추출
- "39,900원" → price_amount: 39900
- "30% 할인" → discount_rate: "30%"

JSON 형식으로만 응답:
{"fields": {...}, "missing_fields": [...]}
"""

MEMO_PROMPT = """당신은 텍스트 정보를 구조화하는 AI입니다.

아래 텍스트에서 다음 필드를 추출하세요:

## 필수 필드
- body: 핵심 텍스트 내용 (원문을 정리하되, 의미 보존)

## 선택 필드
- title: 제목 (없으면 body 첫 문장에서 자동 생성)
- source: 출처 (뉴스 매체, 앱 이름 등)
- tags: 관련 태그 (리스트, 예: ["건강", "운동"])
- date: 관련 날짜 (있으면)

## 규칙
- body는 OCR 오류를 자연스럽게 교정
- 불필요한 UI 요소(좋아요, 공유 버튼 텍스트 등)는 제거
- title이 없으면 body 첫 20자를 title로 사용

JSON 형식으로만 응답:
{"fields": {...}, "missing_fields": [...]}
"""

# 프롬프트 매핑
TYPE_PROMPTS = {
    "SCHEDULE": SCHEDULE_PROMPT,
    "PLACE": PLACE_PROMPT,
    "WISHLIST": WISHLIST_PROMPT,
    "MEMO": MEMO_PROMPT,
}

def get_system_prompt():
    """기존 호환용 (1단계 통합 프롬프트)"""
    return CLASSIFY_PROMPT

def get_type_prompt(screenshot_type: str) -> str:
    """타입별 상세 추출 프롬프트"""
    return TYPE_PROMPTS.get(screenshot_type, MEMO_PROMPT)
```

### 2단계 분석 로직 업그레이드

`app/routers/analyze.py`에 2단계 처리 추가:

```python
@router.post("/analyze/v2", response_model=AnalyzeResponse)
def analyze_v2(request: AnalyzeRequest):
    """2단계 분석: 분류 → 타입별 상세 추출"""
    
    # === 1단계: 분류 ===
    classify_resp = client.chat.completions.create(
        model=OPENAI_MODEL,
        messages=[
            {"role": "system", "content": CLASSIFY_PROMPT},
            {"role": "user", "content": request.ocr_text}
        ],
        response_format={"type": "json_object"},
        temperature=0.1
    )
    classify_result = json.loads(classify_resp.choices[0].message.content)
    detected_type = classify_result.get("type", "MEMO")
    
    # === 2단계: 타입별 상세 추출 ===
    extract_resp = client.chat.completions.create(
        model=OPENAI_MODEL,
        messages=[
            {"role": "system", "content": get_type_prompt(detected_type)},
            {"role": "user", "content": request.ocr_text}
        ],
        response_format={"type": "json_object"},
        temperature=0.1
    )
    extract_result = json.loads(extract_resp.choices[0].message.content)
    
    # 결과 합치기
    final = {
        "type": detected_type,
        "confidence": classify_result.get("confidence", 0),
        "fields": extract_result.get("fields", {}),
        "missing_fields": extract_result.get("missing_fields", [])
    }
    final = validate_result(final)
    
    row_id = save_result(
        type=final["type"],
        confidence=final.get("confidence", 0),
        fields=json.dumps(final.get("fields", {}), ensure_ascii=False)
    )
    
    return AnalyzeResponse(
        id=row_id,
        type=final["type"],
        confidence=final.get("confidence", 0),
        fields=final.get("fields", {}),
        missing_fields=final.get("missing_fields", []),
        status=final.get("status", "DRAFT")
    )
```

### 테스트용 샘플 텍스트 4종

아래 텍스트로 `/docs`에서 테스트해보세요:

```
SCHEDULE 테스트:
"[기프티콘] 투썸플레이스 스트로베리 라떼\n유효기간: 2026.09.30\n교환처: 투썸플레이스 전 매장\n바코드: {MASKED_CARD}"

PLACE 테스트:
"을지다락 ★4.5\n서울 중구 을지로 115\n영업시간 11:00-22:00\n한식, 분위기 좋은 식당\n추천: 된장찌개, 제육볶음"

WISHLIST 테스트:
"나이키 에어맥스 90\n129,000원 → 89,900원 (30% 할인)\n무신사 | 무료배송\n사이즈: 270"

MEMO 테스트:
"하루 물 2리터 마시기의 효과\n1. 피부 개선\n2. 신진대사 촉진\n3. 두통 예방\n- 출처: 헬스조선 2026.06.15"
```

### ✅ Day 10 체크리스트
- [ ] `prompts.py`에 4개 타입 전용 프롬프트가 완성되었다
- [ ] `/analyze/v2` 엔드포인트가 2단계로 동작한다
- [ ] 4개 샘플 텍스트가 각각 올바른 타입으로 분류된다
- [ ] 커밋: `feat: 타입별 전용 프롬프트 + 2단계 분석 API`

---

## Day 11 (목) — 에러 핸들링 + 재시도 로직

> [!TIP]
> 오늘의 목표: 서버가 절대 죽지 않게 만들기

실제로 LLM 호출은 **네트워크 에러, 타임아웃, 이상한 응답** 등이 자주 생겨요.

**`app/llm_client.py`** — 안전한 LLM 호출기:

```python
from openai import OpenAI, APIError, APITimeoutError, RateLimitError
from app.config import OPENAI_MODEL, LLM_TEMPERATURE
import json
import time
import logging

logger = logging.getLogger(__name__)
client = OpenAI()

def call_llm(system_prompt: str, user_text: str, max_retries: int = 3) -> dict:
    """
    LLM을 안전하게 호출하는 함수
    - 실패 시 최대 3번 재시도
    - JSON 파싱 실패 시 기본값 반환
    """
    last_error = None
    
    for attempt in range(max_retries):
        try:
            response = client.chat.completions.create(
                model=OPENAI_MODEL,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_text}
                ],
                response_format={"type": "json_object"},
                temperature=LLM_TEMPERATURE,
                timeout=30  # 30초 타임아웃
            )
            
            result = json.loads(response.choices[0].message.content)
            logger.info(f"LLM 호출 성공 (시도 {attempt + 1})")
            return result
            
        except (APITimeoutError, APIError) as e:
            last_error = e
            wait_time = 2 ** attempt  # 1초, 2초, 4초 대기
            logger.warning(f"LLM 호출 실패 (시도 {attempt + 1}): {e}. {wait_time}초 후 재시도")
            time.sleep(wait_time)
            
        except RateLimitError as e:
            last_error = e
            logger.warning(f"API 호출 한도 초과. 10초 대기 후 재시도")
            time.sleep(10)
            
        except json.JSONDecodeError as e:
            last_error = e
            logger.error(f"JSON 파싱 실패: {e}")
            # JSON이 깨졌으면 재시도
            continue
    
    # 모든 재시도 실패
    logger.error(f"LLM 호출 최종 실패: {last_error}")
    return {
        "type": "MEMO",
        "confidence": 0.0,
        "fields": {},
        "missing_fields": ["LLM 호출 실패 - 수동 입력 필요"],
        "error": str(last_error)
    }
```

그리고 `app/routers/analyze.py`에서 기존 `client.chat.completions.create(...)` 대신 `call_llm()`을 사용하면 돼요.

### ✅ Day 11 체크리스트
- [ ] 네트워크 끊어도 서버가 500 에러 대신 정상 응답을 준다
- [ ] 재시도 로직이 로그에 찍힌다
- [ ] 최종 실패 시 "수동 입력 필요" 상태가 반환된다
- [ ] 커밋: `feat: LLM 호출 재시도 + 에러 핸들링`

---

## Day 12 (금) — 카카오톡 캘린더 API 조사

> [!NOTE]
> 실제 연동은 6주차에 하지만, **지금 미리 조사**해두면 나중에 훨씬 빨라요.

### 조사할 것

1. **카카오 개발자 사이트**: https://developers.kakao.com
   - 톡캘린더 API 문서 읽기
   - REST API 사용에 필요한 앱 키 발급 방법
   
2. **확인해야 할 질문들**:
   - [ ] 일정 등록 API 엔드포인트는?
   - [ ] reminders 파라미터로 D-7, D-1 알림을 설정할 수 있나?
   - [ ] 사용자 인증(OAuth)은 어떻게 하나?
   - [ ] API 호출 제한(Rate Limit)은?
   - [ ] 무료 사용 범위는?

3. **대안 조사** (카카오가 안 되면):
   - Google Calendar API
   - 앱 내 자체 푸시 알림 (Flutter 측에서 처리)

### 산출물: 간단한 조사 메모

```markdown
## 카카오톡 캘린더 API 조사 결과

### 가능 여부: O / X / 조건부
### 필요한 키/인증: ...
### 일정 등록 API: ...
### 알림(reminders) 지원: ...
### 제한 사항: ...
### 대안: ...
```

### ✅ Day 12 체크리스트
- [ ] 카카오 개발자 계정이 생성되었다
- [ ] 톡캘린더 API 문서를 읽고 메모를 작성했다
- [ ] 연동 가능/불가능 판단이 되었다

---

## Day 13~14 (주말) — 통합 테스트 + 회고

### Day 13: 전체 흐름 테스트

다양한 스크린샷 OCR 텍스트를 만들어서 서버에 보내보세요:

```python
# tests/test_analyze.py
import requests

BASE = "http://127.0.0.1:8000/api"

test_cases = [
    {
        "name": "기프티콘",
        "ocr_text": "카카오프렌즈 춘식이 인형\n유효기간: 2026.12.31\n교환처: 카카오프렌즈 매장",
        "expected_type": "SCHEDULE"
    },
    {
        "name": "맛집",
        "ocr_text": "해운대 소문난 돼지국밥\n부산 해운대구 중동\n평점 4.3 | 리뷰 2,847개",
        "expected_type": "PLACE"
    },
    {
        "name": "쇼핑",
        "ocr_text": "애플 에어팟 프로 2세대\n359,000원 → 289,000원\n쿠팡 로켓배송",
        "expected_type": "WISHLIST"
    },
    {
        "name": "메모",
        "ocr_text": "2026학년도 2학기 수강신청 안내\n기간: 8월 18일 ~ 8월 22일\n학교 포털 사이트 참조",
        "expected_type": "SCHEDULE"  # 또는 MEMO (둘 다 가능)
    },
]

for tc in test_cases:
    resp = requests.post(f"{BASE}/analyze/v2", json={
        "ocr_text": tc["ocr_text"],
        "masked_tokens": []
    })
    result = resp.json()
    match = "✅" if result["type"] == tc["expected_type"] else "❌"
    print(f"{match} [{tc['name']}] 예상: {tc['expected_type']} → 결과: {result['type']} (신뢰도: {result['confidence']})")
    print(f"   필드: {result['fields']}")
    print()
```

```powershell
# 서버 실행 중인 상태에서 다른 터미널에서:
pip install requests  # 처음만
python tests/test_analyze.py
```

### Day 14: 2주차 정리 + 커밋

```powershell
git add .
git commit -m "feat: 2주차 완료 - 프로젝트 구조화, 프롬프트 튜닝, 에러 핸들링, 테스트"
git push
```

### ✅ Day 13~14 체크리스트
- [ ] 4종 테스트 케이스 중 3개 이상 정확히 분류된다
- [ ] 에러 상황 테스트 완료 (빈 텍스트, 너무 긴 텍스트 등)
- [ ] 모든 코드가 커밋 + 푸시되었다
- [ ] 팀 회의에서 진행 상황을 공유했다

---

## 📊 2주차 끝나면 이런 상태!

```
Week 1: main.py 하나에 모든 코드
         ↓
Week 2: 
app/
├── main.py          ← 앱 진입점
├── config.py        ← 설정 관리
├── schemas.py       ← 데이터 형식
├── prompts.py       ← 4종 전용 프롬프트 ⭐
├── database.py      ← DB 관리
├── validator.py     ← 검증 레이어
├── llm_client.py    ← 안전한 LLM 호출 ⭐
└── routers/
    ├── analyze.py   ← 분석 API (v1 + v2)
    └── results.py   ← 결과 조회/승인 API
```

> [!IMPORTANT]
> **3주차 미리보기**: 정채윤(AI모델)·공다은(Flutter앱)과 합쳐서 **End-to-End 파이프라인 데모**를 만들 거예요. 2주차에 서버가 튼튼하게 준비되어 있으면 통합이 훨씬 수월해요!
