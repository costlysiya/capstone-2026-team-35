# 🎯 오예린의 백엔드 온보딩 가이드

> 노베이스 → 소생 앱 백엔드 개발자까지, 하루하루 따라하기

---

## 전체 그림: 내가 만들어야 할 것

```
[Flutter 앱] → 텍스트 전송 → [내가 만드는 서버(FastAPI)] → OpenAI 호출 → JSON 반환 → [Flutter 앱]
```

쉽게 말하면:
1. **앱에서 텍스트가 날아오면** 받아서
2. **OpenAI(ChatGPT)한테 "이거 분석해줘" 하고** 보내고
3. **결과를 정리해서** 앱에 돌려주는 서버를 만드는 거예요

---

## 📦 Day 1 — 개발 환경 세팅

> [!TIP]
> 오늘의 목표: Python이 내 컴퓨터에서 돌아가는 것을 확인하기

### 1단계: Python 설치

1. https://www.python.org/downloads/ 에서 **Python 3.11 이상** 다운로드
2. 설치할 때 ⚠️ **"Add Python to PATH" 반드시 체크!**
3. 설치 후 터미널(PowerShell)에서 확인:

```powershell
python --version
# Python 3.11.x 나오면 성공!
```

### 2단계: VS Code 설치 (이미 있으면 스킵)

1. https://code.visualstudio.com/ 에서 다운로드
2. 확장(Extensions)에서 **Python** 검색해서 설치 (Microsoft 공식)

### 3단계: 프로젝트 폴더 만들기

```powershell
# 원하는 위치에 폴더 만들기
mkdir C:\projects\soseng-backend
cd C:\projects\soseng-backend

# 가상환경 만들기 (프로젝트별로 패키지를 분리하는 것)
python -m venv venv

# 가상환경 활성화
.\venv\Scripts\Activate

# 활성화되면 프롬프트 앞에 (venv) 가 붙어요
```

> [!IMPORTANT]
> 매번 작업 시작할 때 `.\venv\Scripts\Activate` 를 실행해야 합니다!
> VS Code 터미널에서 하면 자동으로 잡아주기도 해요.

### 4단계: 필요한 패키지 설치

```powershell
pip install fastapi uvicorn openai python-dotenv
```

| 패키지 | 하는 일 |
|--------|---------|
| `fastapi` | 서버 프레임워크 (서버 만드는 도구) |
| `uvicorn` | 서버를 실행해주는 도구 |
| `openai` | ChatGPT API를 쉽게 쓰게 해주는 도구 |
| `python-dotenv` | API 키 같은 비밀 정보를 안전하게 관리 |

### ✅ Day 1 체크리스트
- [ ] `python --version` 이 정상 출력된다
- [ ] VS Code에서 Python 확장이 설치되어 있다
- [ ] 가상환경이 활성화된다 (`(venv)` 표시)
- [ ] 패키지 4개가 설치되었다

---

## 🚀 Day 2 — 첫 번째 서버 만들기 (FastAPI)

> [!TIP]
> 오늘의 목표: "Hello World" 서버를 띄우고 브라우저에서 확인하기

### 1단계: 첫 서버 코드 작성

`main.py` 파일을 만들고:

```python
from fastapi import FastAPI

app = FastAPI()

# 1. 가장 기본: 브라우저에서 접속하면 인사하기
@app.get("/")
def read_root():
    return {"message": "소생 앱 서버가 돌아가고 있어요! 🎉"}

# 2. 텍스트를 받아서 그대로 돌려주기 (에코 테스트)
@app.post("/echo")
def echo(text: str):
    return {"you_said": text}
```

### 2단계: 서버 실행

```powershell
uvicorn main:app --reload
```

- `main` = main.py 파일
- `app` = 코드에서 만든 FastAPI 객체
- `--reload` = 코드 수정하면 자동으로 서버 재시작

### 3단계: 확인

1. 브라우저에서 http://127.0.0.1:8000 접속 → 메시지 확인!
2. 브라우저에서 http://127.0.0.1:8000/docs 접속 → **자동 생성된 API 문서!**
   - 여기서 "Try it out" 버튼으로 API를 직접 테스트할 수 있어요

### 💡 핵심 개념 정리

```
@app.get("/")     → GET 요청: 정보를 "가져올 때" (브라우저 주소창)
@app.post("/echo") → POST 요청: 정보를 "보낼 때" (앱에서 데이터를 서버로 보냄)
```

Flutter 앱에서 우리 서버로 텍스트를 보낼 때는 **POST** 방식을 사용해요.

### ✅ Day 2 체크리스트
- [ ] http://127.0.0.1:8000 에서 JSON 응답을 볼 수 있다
- [ ] http://127.0.0.1:8000/docs 에서 API 문서가 보인다
- [ ] `/docs`에서 echo API를 테스트해볼 수 있다

---

## 🤖 Day 3 — OpenAI API 연동하기

> [!TIP]
> 오늘의 목표: ChatGPT에게 코드로 질문하고 답을 받아보기

### 1단계: API 키 발급

1. https://platform.openai.com/ 접속 → 회원가입/로그인
2. Settings → API keys → "Create new secret key"
3. 키를 복사 (⚠️ **한 번만 보여줘요! 반드시 어딘가에 저장**)

### 2단계: API 키를 안전하게 저장

프로젝트 폴더에 `.env` 파일 생성:

```
OPENAI_API_KEY=sk-여기에-복사한-키-붙여넣기
```

> [!CAUTION]
> `.env` 파일은 절대 Git에 올리면 안 됩니다! `.gitignore`에 반드시 추가하세요.

### 3단계: ChatGPT에게 코드로 물어보기

`test_openai.py` 파일을 만들고:

```python
from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()  # .env 파일에서 API 키 읽어오기
client = OpenAI()  # 자동으로 OPENAI_API_KEY 환경변수를 사용

# ChatGPT에게 물어보기
response = client.chat.completions.create(
    model="gpt-4o-mini",        # 저렴하고 빠른 모델 (테스트용)
    messages=[
        {"role": "system", "content": "너는 한국어로 답하는 도우미야."},
        {"role": "user", "content": "스크린샷에서 기프티콘 유효기간을 추출하려면 어떻게 해?"}
    ]
)

# 답변 출력
print(response.choices[0].message.content)
```

실행:
```powershell
python test_openai.py
```

### 4단계: 진짜 프로젝트처럼 — 구조화된 응답 받기

이게 **소생 앱에서 실제로 할 일**이에요! `test_structured.py`:

```python
from openai import OpenAI
from dotenv import load_dotenv
import json

load_dotenv()
client = OpenAI()

# 이런 OCR 텍스트가 앱에서 날아온다고 가정
ocr_text = """
[기프티콘] 스타벅스 아메리카노 T
유효기간: 2026.08.15
교환처: 스타벅스 전 매장
바코드: {MASKED_CARD}
"""

response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[
        {
            "role": "system",
            "content": """당신은 스크린샷 OCR 텍스트를 분석하는 AI입니다.
아래 4가지 타입 중 하나로 분류하고, 핵심 필드를 추출하세요:
- SCHEDULE: 기프티콘, 구독, 일정 (expires_at, title 필수)
- PLACE: 맛집, 카페 (name 또는 region 필수)  
- WISHLIST: 쇼핑 (product_name, price_amount 필수)
- MEMO: 텍스트 정보 (body 필수)

반드시 JSON 형식으로만 응답하세요."""
        },
        {
            "role": "user",
            "content": ocr_text
        }
    ],
    response_format={"type": "json_object"}  # JSON 강제!
)

result = json.loads(response.choices[0].message.content)
print(json.dumps(result, ensure_ascii=False, indent=2))
```

실행하면 이런 식으로 나와요:
```json
{
  "type": "SCHEDULE",
  "confidence": 0.95,
  "fields": {
    "title": "스타벅스 아메리카노 T",
    "expires_at": "2026-08-15"
  },
  "missing_fields": [],
  "masked_tokens": ["MASKED_CARD"]
}
```

🎉 **축하해요!** 이게 소생 앱 서버의 핵심 로직이에요!

### ✅ Day 3 체크리스트
- [ ] OpenAI API 키가 발급되어 `.env`에 저장되었다
- [ ] `test_openai.py`로 ChatGPT 답변을 받아봤다
- [ ] `test_structured.py`로 JSON 구조화 응답을 받아봤다

---

## 🔗 Day 4 — 서버에 AI 붙이기

> [!TIP]
> 오늘의 목표: Day 2의 서버 + Day 3의 AI를 합치기!

### 완성된 서버 코드

`main.py`를 아래로 교체:

```python
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from openai import OpenAI
from dotenv import load_dotenv
import json

load_dotenv()
client = OpenAI()
app = FastAPI(title="소생 앱 API")


# --- 요청/응답 데이터 형식 정의 ---

class AnalyzeRequest(BaseModel):
    """앱에서 보내는 요청"""
    ocr_text: str                # OCR로 추출한 텍스트
    masked_tokens: list[str] = []  # 마스킹된 토큰 목록

class AnalyzeResponse(BaseModel):
    """서버가 돌려주는 응답"""
    type: str          # SCHEDULE, PLACE, WISHLIST, MEMO
    confidence: float  # 신뢰도 0.0 ~ 1.0
    fields: dict       # 추출된 필드들
    missing_fields: list[str] = []  # 누락된 필수 필드


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

@app.get("/")
def health_check():
    return {"status": "running", "service": "소생 앱 API"}


@app.post("/analyze", response_model=AnalyzeResponse)
def analyze_screenshot(request: AnalyzeRequest):
    """
    앱에서 OCR 텍스트를 받아 → LLM으로 분석 → 구조화된 결과 반환
    """
    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": request.ocr_text}
            ],
            response_format={"type": "json_object"},
            temperature=0.1  # 낮을수록 일관된 답변
        )

        result = json.loads(response.choices[0].message.content)

        return AnalyzeResponse(
            type=result.get("type", "MEMO"),
            confidence=result.get("confidence", 0.0),
            fields=result.get("fields", {}),
            missing_fields=result.get("missing_fields", [])
        )

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"분석 실패: {str(e)}")
```

### 서버 실행 후 테스트

```powershell
uvicorn main:app --reload
```

http://127.0.0.1:8000/docs 에서:
1. **POST /analyze** 클릭
2. "Try it out" 클릭
3. Request body에 입력:
```json
{
  "ocr_text": "[기프티콘] 투썸플레이스 아이스 아메리카노\n유효기간: 2026.09.30\n교환처: 투썸플레이스 전 매장",
  "masked_tokens": []
}
```
4. "Execute" 클릭 → 결과 확인!

### ✅ Day 4 체크리스트
- [ ] `/analyze` 엔드포인트가 동작한다
- [ ] 기프티콘 텍스트 → SCHEDULE 타입으로 분류된다
- [ ] 맛집 텍스트 → PLACE 타입으로 분류된다
- [ ] `/docs`에서 모든 API를 테스트할 수 있다

---

## 🗄️ Day 5 — 데이터베이스 기초 (SQLite)

> [!TIP]
> 오늘의 목표: 분석 결과를 저장하고 다시 불러올 수 있게 만들기

### SQLite는 설치가 필요 없어요!
Python에 이미 포함되어 있어요. 파일 하나가 곧 데이터베이스예요.

### 1단계: DB 모듈 만들기

`database.py` 파일 생성:

```python
import sqlite3
from datetime import datetime

DB_PATH = "soseng.db"

def get_db():
    """DB 연결 가져오기"""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row  # 딕셔너리처럼 접근 가능
    return conn

def init_db():
    """테이블 생성 (앱 시작할 때 한 번)"""
    conn = get_db()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS screenshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            confidence REAL,
            fields TEXT,
            status TEXT DEFAULT 'DRAFT',
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    conn.close()

def save_result(type: str, confidence: float, fields: str):
    """분석 결과 저장"""
    conn = get_db()
    cursor = conn.execute(
        "INSERT INTO screenshots (type, confidence, fields) VALUES (?, ?, ?)",
        (type, confidence, fields)
    )
    conn.commit()
    row_id = cursor.lastrowid
    conn.close()
    return row_id

def get_all_results():
    """저장된 모든 결과 조회"""
    conn = get_db()
    rows = conn.execute("SELECT * FROM screenshots ORDER BY created_at DESC").fetchall()
    conn.close()
    return [dict(row) for row in rows]

def update_status(id: int, status: str):
    """상태 업데이트 (DRAFT → CONFIRMED)"""
    conn = get_db()
    conn.execute("UPDATE screenshots SET status = ? WHERE id = ?", (status, id))
    conn.commit()
    conn.close()
```

### 2단계: main.py에 DB 연결

`main.py` 맨 위에 import 추가하고 엔드포인트 추가:

```python
# 기존 import에 추가
from database import init_db, save_result, get_all_results, update_status

# 서버 시작할 때 DB 초기화
@app.on_event("startup")
def startup():
    init_db()

# /analyze 의 return 직전에 저장 로직 추가:
# row_id = save_result(result["type"], result["confidence"], json.dumps(result["fields"]))

# 저장된 결과 목록 조회
@app.get("/results")
def list_results():
    return get_all_results()

# 사용자 승인
@app.post("/results/{id}/confirm")
def confirm_result(id: int):
    update_status(id, "CONFIRMED")
    return {"message": f"결과 #{id}이 승인되었습니다"}
```

### ✅ Day 5 체크리스트
- [ ] `soseng.db` 파일이 생성된다
- [ ] `/analyze` 호출 시 결과가 DB에 저장된다
- [ ] `/results` 로 저장된 결과 목록을 볼 수 있다
- [ ] `/results/{id}/confirm` 으로 승인 상태를 바꿀 수 있다

---

## 🛡️ Day 6 — 검증 레이어 만들기

> [!TIP]
> 오늘의 목표: LLM이 이상한 답을 줘도 앱이 안 죽게 방어하기

```python
# validator.py

REQUIRED_FIELDS = {
    "SCHEDULE": ["title"],           # + expires_at 또는 start_at 중 하나
    "PLACE":    [],                   # name 또는 region 중 하나
    "WISHLIST": ["product_name", "price_amount"],
    "MEMO":     ["body"]
}

VALID_TYPES = {"SCHEDULE", "PLACE", "WISHLIST", "MEMO"}

def validate_result(result: dict) -> dict:
    """
    LLM 응답을 검증하고 부족한 부분을 표시
    """
    errors = []
    
    # 1) 타입 검증
    result_type = result.get("type", "")
    if result_type not in VALID_TYPES:
        errors.append(f"알 수 없는 타입: {result_type}")
        result["type"] = "MEMO"  # 기본값으로 폴백
    
    # 2) 신뢰도 검증
    confidence = result.get("confidence", 0)
    if not (0 <= confidence <= 1):
        result["confidence"] = max(0, min(1, confidence))
    
    # 3) 필수 필드 검증
    fields = result.get("fields", {})
    missing = []
    
    for req_field in REQUIRED_FIELDS.get(result["type"], []):
        if req_field not in fields or not fields[req_field]:
            missing.append(req_field)
    
    # 타입별 특수 검증
    if result["type"] == "SCHEDULE":
        if "expires_at" not in fields and "start_at" not in fields:
            missing.append("expires_at 또는 start_at")
    
    if result["type"] == "PLACE":
        if "name" not in fields and "region" not in fields:
            missing.append("name 또는 region")
    
    result["missing_fields"] = missing
    
    # 4) 상태 결정
    if missing:
        result["status"] = "NEEDS_EDIT"   # 수정 필요
    elif confidence < 0.7:
        result["status"] = "LOW_CONFIDENCE"  # 신뢰도 낮음
    else:
        result["status"] = "DRAFT"        # 정상 초안
    
    return result
```

### ✅ Day 6 체크리스트
- [ ] 필수 필드가 빠졌을 때 `missing_fields`에 표시된다
- [ ] 이상한 타입이 오면 MEMO로 폴백된다
- [ ] 신뢰도가 낮으면 `LOW_CONFIDENCE` 상태가 된다

---

## 📚 Day 7 — 정리 + 다음 단계 준비

### 지금까지 만든 것 정리

```
soseng-backend/
├── venv/              ← 가상환경
├── .env               ← API 키 (Git에 올리지 말 것!)
├── .gitignore         ← venv, .env, soseng.db 제외
├── main.py            ← FastAPI 서버 (핵심)
├── database.py        ← SQLite DB 관리
├── validator.py       ← LLM 응답 검증
├── test_openai.py     ← OpenAI 테스트용
└── requirements.txt   ← 의존성 목록
```

### requirements.txt 만들기

```powershell
pip freeze > requirements.txt
```

### .gitignore 만들기

```
venv/
.env
soseng.db
__pycache__/
*.pyc
```

---

## 🎓 추천 학습 자료

### 지금 당장 보면 좋은 것 (한국어)

| 주제 | 자료 | 예상 시간 |
|------|------|----------|
| Python 기초 | [점프 투 파이썬](https://wikidocs.net/book/1) (무료) | 필요한 부분만 1~2시간 |
| FastAPI 입문 | [FastAPI 공식 튜토리얼 (한국어)](https://fastapi.tiangolo.com/ko/tutorial/) | 2~3시간 |
| REST API 개념 | YouTube에서 "REST API 개념 정리" 검색 | 30분 |

### 나중에 필요할 때 보면 좋은 것

| 주제 | 시기 |
|------|------|
| 카카오톡 캘린더 API 연동 | 6주차 |
| 서버 배포 (AWS/GCP) | 7주차 이후 |
| 에러 핸들링·로깅 | 7주차 |

---

## 💬 모르면 이렇게 검색하세요

| 상황 | 검색어 |
|------|--------|
| 에러 났을 때 | 에러 메시지 전체를 복사해서 구글에 검색 |
| FastAPI 사용법 | `fastapi [하고싶은것] python` |
| OpenAI 사용법 | `openai api [하고싶은것] python` |
| SQL 문법 | `sqlite [하고싶은것] python` |

> [!TIP]
> **ChatGPT에게 물어봐도 돼요!** "FastAPI에서 파일 업로드 받으려면 어떻게 해?" 같이 구체적으로 물어보면 코드까지 알려줘요. 팀 프로젝트니까 정채윤 팀장한테도 편하게 물어보세요 😊
