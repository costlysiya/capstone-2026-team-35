# 4주차 (Day 22~28) — 배치 처리 · 캐싱 · 타입별 요구사항 정밀화

> [!IMPORTANT]
> 3주차까지 **단건 분석 파이프라인**이 완성되었습니다.
> 4주차에는 실전 사용 시나리오에 맞춰 **배치(다건) 처리**, **중복 방지 캐싱**,
> **타입별 필드 요구사항 정밀화**, **마스킹 토큰 로컬 저장 지원**을 구현합니다.

---

## 🗓️ 4주차 전체 로드맵

| Day | 테마 | 핵심 작업 |
|-----|-------|----------|
| 22 | 배치 분석 API | 복수 이미지를 한 번에 분석 요청하는 `/api/analyze/batch` |
| 23 | 이미지 해시 캐싱 | 동일 이미지 재분석 방지 (image_hash 기반 캐시) |
| 24 | 동시성 제한 | LLM 호출 세마포어로 단말 과부하·비용 폭증 방지 |
| 25 | SCHEDULE 타입 정밀화 | 기프티콘/구독만료/일반일정 sub_type별 자동 오토필 + 캘린더 연동 필드 |
| 26 | PLACE·WISHLIST·MEMO 정밀화 | 타입별 필수·선택 필드 재정의 + 사진 보관 여부 메타데이터 |
| 27 | 마스킹 토큰 로컬 저장 지원 | masked_tokens 원본 복원 정보를 별도 저장하는 API |
| 28 | 통합 테스트 + 정리 | 배치·캐싱·타입별 통합 테스트 및 커밋 |

---

## Day 22 (월) — 배치 분석 API

> [!TIP]
> 오늘의 목표: 앱에서 사진을 여러 장 선택했을 때 한 번의 요청으로 전부 분석을 요청하는 배치 API 구현

### 현재 상황
- 지금은 사진 1장마다 `/api/analyze/v2`를 한 번씩 호출합니다.
- 사용자가 50장을 올리면 50번 호출 → 비효율적이고 앱에서 순차 호출하기 복잡합니다.

### 1단계: 스키마 추가

`app/schemas.py`에 배치 요청/응답 스키마 추가:

```python
class BatchAnalyzeRequest(BaseModel):
    """배치 분석 요청 — 복수 이미지를 한 번에"""
    items: list[AnalyzeRequest]  # 최대 20개까지

    class Config:
        json_schema_extra = {
            "example": {
                "items": [
                    {"ocr_text": "스타벅스 아메리카노\n유효기간: 2026.08.15", "type": "SCHEDULE", "masked_tokens": []},
                    {"ocr_text": "을지다락 ★4.5\n서울 중구", "type": "PLACE", "masked_tokens": []}
                ]
            }
        }

class BatchAnalyzeResponse(BaseModel):
    """배치 분석 응답"""
    total: int
    success: int
    failed: int
    results: list[AnalyzeResponse]
    errors: list[dict] = []
```

### 2단계: 배치 엔드포인트 구현

`app/routers/analyze.py`에 추가:

```python
from app.schemas import BatchAnalyzeRequest, BatchAnalyzeResponse

@router.post("/analyze/batch", response_model=BatchAnalyzeResponse)
def analyze_batch(request: BatchAnalyzeRequest):
    """
    복수 이미지를 한 번에 분석.
    각 항목을 순차적으로 처리하고 결과를 모아서 반환.
    최대 20개까지 허용.
    """
    if len(request.items) > 20:
        raise HTTPException(
            status_code=400,
            detail="배치 요청은 최대 20개까지 가능합니다"
        )

    results = []
    errors = []

    for idx, item in enumerate(request.items):
        try:
            # 기존 analyze_v2 로직을 재사용
            response = analyze_v2(item)
            results.append(response)
        except Exception as e:
            logger.error(f"[batch] 항목 {idx} 실패: {e}")
            errors.append({"index": idx, "error": str(e)})

    return BatchAnalyzeResponse(
        total=len(request.items),
        success=len(results),
        failed=len(errors),
        results=results,
        errors=errors
    )
```

### ✅ Day 22 체크리스트
- [ ] `BatchAnalyzeRequest`, `BatchAnalyzeResponse` 스키마 추가
- [ ] `POST /api/analyze/batch` 엔드포인트 구현
- [ ] 20개 초과 요청 시 400 에러 반환 확인
- [ ] `/docs`에서 2~3개 항목 배치 테스트 성공
- [ ] 커밋: `feat: 배치 분석 API 구현 (/api/analyze/batch)`

---

## Day 23 (화) — 이미지 해시 기반 캐싱 (중복 분석 방지)

> [!TIP]
> 오늘의 목표: 동일한 이미지를 또 분석하지 않도록 해시 기반 캐시를 도입

### 현재 상황
- 사용자가 같은 스크린샷을 실수로 2번 업로드하면, LLM 호출이 2번 발생합니다 → 비용 낭비

### 1단계: DB 스키마 확장

`app/database.py`의 `init_db`에 `image_hash` 컬럼과 캐시 테이블 추가:

```python
def init_db():
    conn = get_db()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS screenshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            confidence REAL,
            fields TEXT,
            status TEXT DEFAULT 'DRAFT',
            image_hash TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    """)
    # 해시 인덱스 (빠른 조회용)
    conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_image_hash ON screenshots(image_hash)
    """)
    conn.commit()
    conn.close()
```

### 2단계: 캐시 조회·저장 함수

`app/database.py`에 추가:

```python
def get_result_by_hash(image_hash: str):
    """이미지 해시로 기존 분석 결과 조회 (캐시 히트 확인)"""
    conn = get_db()
    row = conn.execute(
        "SELECT * FROM screenshots WHERE image_hash = ? ORDER BY created_at DESC LIMIT 1",
        (image_hash,)
    ).fetchone()
    conn.close()
    if row:
        return dict(row)
    return None

def save_result(type: str, confidence: float, fields: str, image_hash: str = None):
    """분석 결과 저장 (image_hash 추가)"""
    conn = get_db()
    cursor = conn.execute(
        "INSERT INTO screenshots (type, confidence, fields, image_hash) VALUES (?, ?, ?, ?)",
        (type, confidence, fields, image_hash)
    )
    conn.commit()
    row_id = cursor.lastrowid
    conn.close()
    return row_id
```

### 3단계: 스키마에 image_hash 필드 추가

`app/schemas.py`의 `AnalyzeRequest`에:

```python
class AnalyzeRequest(BaseModel):
    """앱 → 서버 요청"""
    ocr_text: str
    type: ScreenshotType | None = None
    masked_tokens: list[str] = []
    image_hash: str | None = None  # 🆕 앱에서 보내는 이미지 해시 (SHA-256)
```

### 4단계: analyze_v2에 캐시 로직 적용

`app/routers/analyze.py`의 `analyze_v2` 시작 부분에 추가:

```python
    # 🗃️ 캐시 확인: 동일 이미지가 이미 분석된 적 있으면 재사용
    if request.image_hash:
        cached = get_result_by_hash(request.image_hash)
        if cached:
            logger.info(f"[v2] 🗃️ 캐시 히트! hash={request.image_hash[:16]}...")
            cached_fields = cached["fields"]
            if isinstance(cached_fields, str):
                try:
                    cached_fields = json.loads(cached_fields)
                except json.JSONDecodeError:
                    cached_fields = {}
            return AnalyzeResponse(
                id=cached["id"],
                type=cached["type"],
                confidence=cached["confidence"],
                fields=cached_fields,
                missing_fields=[],
                status=cached["status"]
            )
```

### ✅ Day 23 체크리스트
- [ ] DB에 `image_hash` 컬럼 + 인덱스 추가
- [ ] `get_result_by_hash()` 함수 구현
- [ ] `save_result()`에 `image_hash` 파라미터 추가
- [ ] 같은 해시로 2번 요청 시 LLM 호출 없이 캐시 결과 반환 확인
- [ ] 커밋: `feat: 이미지 해시 기반 캐싱 (중복 분석 방지)`

> [!WARNING]
> DB 스키마가 변경되었으므로, 기존 `soseng.db` 파일을 삭제하고 서버를 다시 시작해야 합니다.
> ```bash
> del soseng.db
> python run.py
> ```

---

## Day 24 (수) — 동시성 제한 (세마포어)

> [!TIP]
> 오늘의 목표: LLM 호출이 동시에 너무 많이 발생하지 않도록 제한

### 현재 상황
- 배치 API를 통해 20개 요청이 한꺼번에 들어오면, OpenAI API를 20번 연속 호출합니다.
- 이는 API 비용 폭증 + 서버 과부하 + 429 Rate Limit 에러의 원인이 됩니다.

### 1단계: 동시성 제어 모듈 생성

`app/concurrency.py` 파일 새로 생성:

```python
import asyncio
import threading
import logging

logger = logging.getLogger(__name__)

# 동시 LLM 호출 최대 수 (동시에 3개까지만 허용)
MAX_CONCURRENT_LLM = 3

# threading 기반 세마포어 (sync 엔드포인트용)
_llm_semaphore = threading.Semaphore(MAX_CONCURRENT_LLM)


def call_llm_with_limit(llm_func, *args, **kwargs):
    """
    세마포어로 동시 LLM 호출 수를 제한.
    MAX_CONCURRENT_LLM개 초과 시 대기열에 들어감.
    """
    logger.info(f"[concurrency] LLM 호출 대기 중... (현재 가용: {_llm_semaphore._value})")
    with _llm_semaphore:
        logger.info(f"[concurrency] LLM 호출 시작 (남은 슬롯: {_llm_semaphore._value})")
        return llm_func(*args, **kwargs)
```

### 2단계: analyze.py에서 적용

`app/routers/analyze.py`에서 `call_llm` 호출을 `call_llm_with_limit`으로 교체:

```python
from app.concurrency import call_llm_with_limit

# 기존:
# classify_result = call_llm(system_prompt=CLASSIFY_PROMPT, ...)
# 변경:
classify_result = call_llm_with_limit(call_llm, system_prompt=CLASSIFY_PROMPT, user_text=request.ocr_text)

# 기존:
# extract_result = call_llm(system_prompt=get_type_prompt(detected_type), ...)
# 변경:
extract_result = call_llm_with_limit(call_llm, system_prompt=get_type_prompt(detected_type), user_text=request.ocr_text)
```

### ✅ Day 24 체크리스트
- [ ] `app/concurrency.py` 모듈 생성 (세마포어 기반)
- [ ] `analyze_v2` 및 `analyze_batch`에서 `call_llm_with_limit` 적용
- [ ] 배치 5개 요청 시 동시 3개 + 2개 대기 로그 확인
- [ ] 커밋: `feat: LLM 동시성 제한 세마포어 도입`

---

## Day 25 (목) — SCHEDULE 타입 정밀화

> [!TIP]
> 오늘의 목표: SCHEDULE 카테고리 안에서 기프티콘 / 구독 만료 / 일반 일정을 세분화하여
> 각각에 맞는 **오토필 필드**와 **캘린더 연동용 필드**를 자동 구성

### 현재 상황
- `sub_type` 필드가 존재하지만, 백엔드에서 이를 활용한 **타입별 차별화된 응답 가공**이 없습니다.
- 앱에서 일정/기프티콘 탭을 분할했으므로, 서버도 이에 맞춰 데이터를 가공해줘야 합니다.

### 1단계: validator.py에 sub_type별 후처리 로직 추가

`app/validator.py`에 함수 추가:

```python
def _enrich_schedule_fields(fields: dict) -> dict:
    """
    SCHEDULE 타입의 sub_type에 따라 자동으로 보강 필드를 채움.
    앱에서 오토필 UI를 그릴 때 사용할 수 있도록.
    """
    sub_type = fields.get("sub_type", "OTHER")

    # 1) 기프티콘: 사진 유지 + 만료 알림 자동 설정
    if sub_type == "GIFTICON":
        fields.setdefault("keep_photo", True)         # 바코드 원본 보관
        fields.setdefault("reminder_days", [7, 3, 1])  # D-7, D-3, D-1
        fields.setdefault("calendar_type", "EXPIRY")   # 만료일 기준 등록

    # 2) 구독 서비스: 반복 주기 + 장기 알림
    elif sub_type == "SUBSCRIPTION":
        fields.setdefault("keep_photo", False)
        fields.setdefault("reminder_days", [30, 7, 1])
        fields.setdefault("calendar_type", "RENEWAL")  # 갱신일 기준
        fields.setdefault("recurrence", "매월")

    # 3) 일반 약속/미팅
    elif sub_type == "APPOINTMENT":
        fields.setdefault("keep_photo", False)          # 사진 삭제
        fields.setdefault("reminder_days", [1])
        fields.setdefault("calendar_type", "EVENT")

    # 4) 티켓 (KTX, 영화, 공연)
    elif sub_type == "TICKET":
        fields.setdefault("keep_photo", True)           # 예매 번호 보관
        fields.setdefault("reminder_days", [3, 1])
        fields.setdefault("calendar_type", "EVENT")

    # 5) 마감/시험
    elif sub_type == "DEADLINE":
        fields.setdefault("keep_photo", False)
        fields.setdefault("reminder_days", [14, 7, 3, 1])
        fields.setdefault("calendar_type", "DEADLINE")

    # 6) 택배/배송
    elif sub_type == "DELIVERY":
        fields.setdefault("keep_photo", False)
        fields.setdefault("reminder_days", [1])
        fields.setdefault("calendar_type", "DELIVERY")

    # 7) 기타/판별 불가
    else:
        fields.setdefault("keep_photo", False)
        fields.setdefault("reminder_days", [1])
        fields.setdefault("calendar_type", "EVENT")

    return fields
```

### 2단계: validate_result에서 자동 호출

`app/validator.py`의 `validate_result()` 함수 안, 상태 결정 직전에 추가:

```python
    # 3.5) SCHEDULE 타입이면 sub_type별 보강 필드 자동 채움
    if result["type"] == "SCHEDULE":
        fields = result.get("fields", {})
        targets = _get_validate_targets(fields)
        for item in targets:
            _enrich_schedule_fields(item)
```

### ✅ Day 25 체크리스트
- [ ] `_enrich_schedule_fields()` 함수 구현
- [ ] `validate_result()`에서 SCHEDULE 타입일 때 자동 호출
- [ ] 기프티콘 텍스트 → `keep_photo: true`, `calendar_type: "EXPIRY"` 확인
- [ ] 구독 만료 텍스트 → `reminder_days: [30, 7, 1]`, `recurrence: "매월"` 확인
- [ ] 일반 약속 텍스트 → `keep_photo: false`, `calendar_type: "EVENT"` 확인
- [ ] 커밋: `feat: SCHEDULE sub_type별 오토필 로직 (캘린더 연동 필드)`

---

## Day 26 (금) — PLACE · WISHLIST · MEMO 타입 정밀화

> [!TIP]
> 오늘의 목표: 나머지 3개 타입도 요구사항에 맞게 보강 필드를 자동으로 채움

### validator.py에 타입별 보강 함수 추가:

```python
def _enrich_place_fields(fields: dict) -> dict:
    """PLACE 타입 보강 — 지도 연동용 필드"""
    fields.setdefault("keep_photo", False)      # 장소는 사진 불필요
    fields.setdefault("map_ready", bool(fields.get("address") or fields.get("region")))
    # category 정규화 (없으면 "기타")
    fields.setdefault("category", "기타")
    return fields


def _enrich_wishlist_fields(fields: dict) -> dict:
    """WISHLIST 타입 보강 — 원본 사진 보관 + 가격 정규화"""
    fields.setdefault("keep_photo", True)       # 상품 원본 이미지 보관
    # 가격 정규화: 문자열이면 숫자만 추출
    price = fields.get("price_amount")
    if isinstance(price, str):
        import re
        nums = re.sub(r'[^\d.]', '', price)
        fields["price_amount"] = float(nums) if nums else None
    return fields


def _enrich_memo_fields(fields: dict) -> dict:
    """MEMO 타입 보강 — 제목 자동 생성 + 사진 삭제"""
    fields.setdefault("keep_photo", False)       # 메모는 사진 삭제
    # 제목이 없으면 body 앞 30자로 자동 생성
    if not fields.get("title") and fields.get("body"):
        body = fields["body"]
        fields["title"] = body[:30] + ("..." if len(body) > 30 else "")
    return fields
```

### validate_result()에 통합 적용:

```python
    # 3.5) 타입별 보강 필드 자동 채움
    fields = result.get("fields", {})
    targets = _get_validate_targets(fields)
    for item in targets:
        if result["type"] == "SCHEDULE":
            _enrich_schedule_fields(item)
        elif result["type"] == "PLACE":
            _enrich_place_fields(item)
        elif result["type"] == "WISHLIST":
            _enrich_wishlist_fields(item)
        elif result["type"] == "MEMO":
            _enrich_memo_fields(item)
```

### 사진 보관 정책 요약 (앱 팀 공유용)

| 타입 | keep_photo | 이유 |
|------|-----------|------|
| SCHEDULE (기프티콘) | `true` | 바코드/쿠폰 원본 필요 |
| SCHEDULE (일반 일정) | `false` | 정보 인덱싱 후 삭제 |
| PLACE | `false` | 텍스트 정보만으로 충분 |
| WISHLIST | `true` | 상품 원본 이미지 참조 필요 |
| MEMO | `false` | 정보 저장 후 사진 삭제 |

### ✅ Day 26 체크리스트
- [ ] PLACE: `map_ready`, `category` 자동 채움 확인
- [ ] WISHLIST: `keep_photo: true`, 가격 정규화 확인
- [ ] MEMO: `keep_photo: false`, 제목 자동 생성 확인
- [ ] 4개 타입 모두에 `keep_photo` 필드가 자동 포함됨을 확인
- [ ] 커밋: `feat: 4종 타입별 보강 필드 자동 채움 (keep_photo, 정규화)`

---

## Day 27 (토) — 마스킹 토큰 로컬 저장 지원 API

> [!TIP]
> 오늘의 목표: 마스킹된 민감정보의 원본-마스크 쌍을 서버가 아닌 로컬에 저장할 수 있도록,
> 서버 응답에 마스킹 정보를 구조화해서 돌려주는 로직 구현

### 배경
- 현재 `masked_tokens`는 앱 → 서버로 전송만 되고, 서버에서 따로 저장하거나 반환하지 않습니다.
- 앱에서 원본 카드번호 등을 사용자 선택에 따라 로컬 DB에 보관하려면, 서버가 **어떤 토큰이 마스킹되었는지**를 응답에 포함해줘야 합니다.

### 1단계: AnalyzeResponse에 masked_info 필드 추가

`app/schemas.py`:

```python
class AnalyzeResponse(BaseModel):
    """서버 → 앱 응답"""
    id: int | None = None
    type: ScreenshotType
    confidence: float
    fields: dict
    missing_fields: list[str] = []
    status: str = "DRAFT"
    masked_info: list[dict] = []  # 🆕 마스킹된 토큰 정보 (앱 로컬 저장용)
```

### 2단계: analyze_v2 응답에 masked_info 포함

`app/routers/analyze.py`의 마지막 return 부분:

```python
    # 마스킹 정보 구조화 (앱이 로컬 DB에 저장할지 결정)
    masked_info = []
    for token in request.masked_tokens:
        masked_info.append({
            "original_hint": token[:4] + "****" if len(token) > 4 else "****",
            "token_type": _detect_token_type(token),  # CARD, SSN, PHONE 등
            "masked_value": token
        })

    return AnalyzeResponse(
        id=row_id,
        type=final["type"],
        confidence=final.get("confidence", 0),
        fields=final.get("fields", {}),
        missing_fields=final.get("missing_fields", []),
        status=final.get("status", "DRAFT"),
        masked_info=masked_info
    )
```

### 3단계: 토큰 타입 판별 헬퍼 함수

`app/routers/analyze.py`에 추가:

```python
import re

def _detect_token_type(token: str) -> str:
    """마스킹된 토큰의 원본 유형을 추정"""
    clean = re.sub(r'[\s\-]', '', token)
    if re.match(r'^\d{13,19}$', clean):
        return "CARD"        # 카드번호
    elif re.match(r'^\d{6}[- ]?\d{7}$', clean):
        return "SSN"         # 주민번호
    elif re.match(r'^0\d{1,2}[- ]?\d{3,4}[- ]?\d{4}$', clean):
        return "PHONE"       # 전화번호
    elif re.match(r'^\d{10,13}$', clean):
        return "BARCODE"     # 바코드
    else:
        return "OTHER"
```

### ✅ Day 27 체크리스트
- [ ] `AnalyzeResponse`에 `masked_info` 필드 추가
- [ ] `_detect_token_type()` 함수로 카드/주민번호/전화번호/바코드 구분
- [ ] 마스킹 토큰 포함 요청 시 `masked_info` 배열이 올바르게 반환됨
- [ ] 마스킹 토큰 없는 요청 시 `masked_info: []` 반환 확인
- [ ] 커밋: `feat: 마스킹 토큰 정보 구조화 응답 (로컬 저장 지원)`

---

## Day 28 (일) — 4주차 통합 테스트 + 정리

> [!TIP]
> 오늘의 목표: 이번 주에 구현한 기능들을 모두 테스트하고, 안정성을 확인한 뒤 최종 커밋

### 통합 테스트 스크립트 (`tests/test_week4.py`)

```python
# 테스트 항목:
# 1. 배치 API — 3개 항목 동시 분석 성공
# 2. 캐시 — 같은 hash로 2번 요청 시 캐시 히트
# 3. 동시성 — 배치 5개 요청 시 로그에 "대기 중" 메시지 확인
# 4. SCHEDULE sub_type — 기프티콘 → keep_photo:true, 일반 → keep_photo:false
# 5. WISHLIST — keep_photo:true, 가격 숫자 정규화
# 6. MEMO — keep_photo:false, 제목 자동 생성
# 7. 마스킹 — masked_tokens 포함 시 masked_info 반환
```

### 테스트 시나리오

```
[시나리오 1: 배치 분석]
POST /api/analyze/batch
→ items 3개 전송 → total:3, success:3, failed:0

[시나리오 2: 캐시 히트]
POST /api/analyze/v2 (image_hash: "abc123")
POST /api/analyze/v2 (image_hash: "abc123")  ← 두 번째는 LLM 호출 없이 캐시 반환

[시나리오 3: sub_type별 오토필]
POST /api/analyze/v2 (기프티콘 텍스트)
→ sub_type: "GIFTICON", keep_photo: true, calendar_type: "EXPIRY"

POST /api/analyze/v2 (넷플릭스 구독 만료 텍스트)
→ sub_type: "SUBSCRIPTION", reminder_days: [30, 7, 1], recurrence: "매월"

[시나리오 4: 마스킹 정보]
POST /api/analyze/v2 (masked_tokens: ["9300-****-****-1234"])
→ masked_info: [{token_type: "CARD", ...}]
```

### ✅ Day 28 체크리스트
- [ ] 7개 시나리오 중 6개 이상 통과
- [ ] 서버 로그에 캐시 히트 / 세마포어 대기 로그가 정상 출력
- [ ] 모든 코드가 커밋 + 푸시
- [ ] 커밋: `test: 4주차 통합 테스트 (배치·캐싱·타입별·마스킹)`

---

## 📋 4주차 전체 커밋 이력 (예상)

```
feat: 배치 분석 API 구현 (/api/analyze/batch)
feat: 이미지 해시 기반 캐싱 (중복 분석 방지)
feat: LLM 동시성 제한 세마포어 도입
feat: SCHEDULE sub_type별 오토필 로직 (캘린더 연동 필드)
feat: 4종 타입별 보강 필드 자동 채움 (keep_photo, 정규화)
feat: 마스킹 토큰 정보 구조화 응답 (로컬 저장 지원)
test: 4주차 통합 테스트 (배치·캐싱·타입별·마스킹)
```

---

## 📌 4주차 끝나면 다은(앱)에게 전달할 사항

4주차가 완료되면, 앱 팀에 아래 변경사항을 공유해야 합니다:

1. **배치 API** (`POST /api/analyze/batch`): 여러 장을 한 번에 보낼 수 있음
2. **image_hash 필드**: 앱에서 이미지의 SHA-256 해시를 함께 보내면 중복 분석 방지
3. **keep_photo 필드**: 서버 응답에 사진 보관 여부가 자동 포함됨 → 앱에서 이 값을 보고 원본 사진 삭제/보관 결정
4. **masked_info 배열**: 마스킹 토큰 유형(카드/주민/전화)이 구조화되어 응답됨 → 앱에서 로컬 저장 여부를 사용자에게 물어볼 때 활용
5. **calendar_type, reminder_days**: SCHEDULE 타입 응답에 캘린더 등록용 메타데이터 자동 포함
