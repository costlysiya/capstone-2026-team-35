# 📅 오예린 3주차 가이드 — 팀 통합 & End-to-End 파이프라인 데모

> **현재 상태**: 2주차 완료 (프로젝트 구조화, 4종 프롬프트, 2단계 분석 API, 에러 핸들링, 복수 항목 추출)  
> **3주차 목표**: 정채윤(AI모델)·공다은(Flutter앱)과 합쳐서 **업로드 → OCR → 마스킹 → LLM → 사용자 승인** 흐름의 End-to-End 데모 완성

---

## 🗺️ 3주차 전체 로드맵

```
Day 15 (월)  API 명세 확정 + CORS 설정 + 앱 연동 준비
Day 16 (화)  결과 조회/수정/삭제 API 완성 (CRUD 풀세트)
Day 17 (수)  LLM 구조화 API 4종 통합 테스트 + 엣지 케이스 방어
Day 18 (목)  검증 레이어 v2 + 사용자 수정 반영 로직
Day 19 (금)  서버 ↔ Flutter 앱 통합 테스트
Day 20~21 (주말)  End-to-End 데모 준비 + 팀 리허설
```

---

## Day 15 (월) — API 명세 확정 + CORS 설정 + 앱 연동 준비

> [!IMPORTANT]
> 오늘의 목표: Flutter 앱(공다은)이 우리 서버에 요청을 보낼 수 있는 환경을 만들기

### 1단계: CORS 설정 (가장 먼저!)

Flutter 앱에서 서버에 요청을 보내면 **CORS(Cross-Origin Resource Sharing) 에러**가 발생해요.
이걸 허용해줘야 앱이 서버와 통신할 수 있습니다.

**`app/main.py`** 수정:

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import init_db
from app.routers import analyze, results

app = FastAPI(
    title="소생 앱 API",
    description="스크린샷 정보 추출 및 관리 서버",
    version="0.2.0"
)

# ✅ CORS 설정 — Flutter 앱에서의 요청을 허용
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],          # 개발 중에는 전체 허용 (배포 시 제한)
    allow_credentials=True,
    allow_methods=["*"],          # GET, POST, PUT, DELETE 모두 허용
    allow_headers=["*"],
)

@app.on_event("startup")
def startup():
    init_db()

# 라우터 연결
app.include_router(analyze.router)
app.include_router(results.router)

@app.get("/")
def health():
    return {"status": "running", "version": "0.2.0"}
```

### 2단계: API 명세서 작성

팀원들(특히 공다은)에게 공유할 API 명세서를 정리하세요.
서버를 실행하면 자동 생성되는 `/docs` 페이지도 있지만, 팀 공유용 간결한 문서가 필요해요.

```markdown
## 소생 앱 API 명세 v0.2

### Base URL
- 로컬: `http://127.0.0.1:8000`
- (배포 후): `https://your-server.com`

### 1. 텍스트 분석 (1단계 — 단일 호출)
POST /api/analyze
- Request: { "ocr_text": "...", "masked_tokens": [] }
- Response: { "id": 1, "type": "SCHEDULE", "confidence": 0.95, "fields": {...}, "missing_fields": [], "status": "DRAFT" }

### 2. 텍스트 분석 (2단계 — 분류 후 상세 추출) ⭐ 메인
POST /api/analyze/v2
- Request: { "ocr_text": "...", "masked_tokens": [] }
- Response: 동일

### 3. 결과 목록 조회
GET /api/results
- Response: [ { "id": 1, "type": "...", "fields": "...", "status": "DRAFT", "created_at": "..." }, ... ]

### 4. 결과 승인
POST /api/results/{id}/confirm
- Response: { "message": "결과 #1이(가) 승인되었습니다" }

### 5. 결과 수정 (NEW — Day 16에 구현)
PUT /api/results/{id}
- Request: { "edited_fields": { ... } }
- Response: 수정된 결과 객체

### 6. 결과 삭제 (NEW — Day 16에 구현)
DELETE /api/results/{id}
- Response: { "message": "결과 #1이(가) 삭제되었습니다" }
```

### 3단계: 팀에게 서버 접속 방법 공유

같은 Wi-Fi 네트워크에서 테스트할 때:

```powershell
# 내 컴퓨터의 로컬 IP 확인
ipconfig

# 결과에서 "IPv4 Address" 확인 (예: 192.168.0.15)
# 서버를 0.0.0.0으로 실행 (이미 run.py에 설정되어 있음)
python run.py
```

공다은에게 전달할 정보:
```
서버 주소: http://192.168.0.15:8000
API 문서: http://192.168.0.15:8000/docs
메인 엔드포인트: POST /api/analyze/v2
```

> [!TIP]
> `192.168.0.15` 부분은 본인 컴퓨터의 실제 IP로 바꿔야 해요. `ipconfig`로 확인!

### ✅ Day 15 체크리스트
- [ ] CORS 미들웨어가 `main.py`에 추가되었다
- [ ] 다른 장치(핸드폰 등)에서 `http://내IP:8000/docs`에 접속 가능하다
- [ ] API 명세서를 작성하고 팀(카톡/노션)에 공유했다
- [ ] 커밋: `feat: CORS 설정 + API 명세 v0.2`

---

## Day 16 (화) — 결과 CRUD 완성 (조회/수정/삭제)

> [!TIP]
> 오늘의 목표: 앱에서 초안 카드를 보여주고, 사용자가 수정·삭제·승인할 수 있도록 API 완성

### 1단계: database.py 업그레이드

기존 `database.py`에 **수정·삭제·단건 조회** 함수를 추가하세요:

```python
import sqlite3
import json
from datetime import datetime

DB_PATH = "soseng.db"

def get_db():
    """DB 연결 가져오기"""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
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
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
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

def get_result_by_id(id: int):
    """단건 조회"""
    conn = get_db()
    row = conn.execute("SELECT * FROM screenshots WHERE id = ?", (id,)).fetchone()
    conn.close()
    if row:
        return dict(row)
    return None

def get_all_results():
    """저장된 모든 결과 조회"""
    conn = get_db()
    rows = conn.execute("SELECT * FROM screenshots ORDER BY created_at DESC").fetchall()
    conn.close()
    return [dict(row) for row in rows]

def get_results_by_type(type: str):
    """타입별 결과 조회"""
    conn = get_db()
    rows = conn.execute(
        "SELECT * FROM screenshots WHERE type = ? ORDER BY created_at DESC",
        (type,)
    ).fetchall()
    conn.close()
    return [dict(row) for row in rows]

def get_results_by_status(status: str):
    """상태별 결과 조회"""
    conn = get_db()
    rows = conn.execute(
        "SELECT * FROM screenshots WHERE status = ? ORDER BY created_at DESC",
        (status,)
    ).fetchall()
    conn.close()
    return [dict(row) for row in rows]

def update_fields(id: int, fields: str):
    """사용자가 수정한 필드 업데이트"""
    conn = get_db()
    now = datetime.now().isoformat()
    conn.execute(
        "UPDATE screenshots SET fields = ?, updated_at = ? WHERE id = ?",
        (fields, now, id)
    )
    conn.commit()
    conn.close()

def update_status(id: int, status: str):
    """상태 업데이트 (DRAFT → CONFIRMED)"""
    conn = get_db()
    now = datetime.now().isoformat()
    conn.execute(
        "UPDATE screenshots SET status = ?, updated_at = ? WHERE id = ?",
        (status, now, id)
    )
    conn.commit()
    conn.close()

def delete_result(id: int):
    """결과 삭제"""
    conn = get_db()
    conn.execute("DELETE FROM screenshots WHERE id = ?", (id,))
    conn.commit()
    conn.close()
```

> [!NOTE]
> `updated_at` 컬럼이 기존 DB에 없을 수 있어요. 기존 `soseng.db` 파일을 삭제하고 서버를 재시작하면 새 스키마로 다시 생성됩니다.
> (개발 중이니 데이터 날려도 괜찮아요!)

### 2단계: results.py 라우터 확장

`app/routers/results.py`를 풀 CRUD로 업그레이드:

```python
from fastapi import APIRouter, HTTPException, Query
from app.database import (
    get_all_results, get_result_by_id, get_results_by_type,
    get_results_by_status, update_status, update_fields, delete_result
)
from app.schemas import ResultConfirmRequest
import json

router = APIRouter(prefix="/api/results", tags=["결과"])


@router.get("")
def list_results(
    type: str | None = Query(None, description="타입 필터 (SCHEDULE, PLACE, WISHLIST, MEMO)"),
    status: str | None = Query(None, description="상태 필터 (DRAFT, CONFIRMED, NEEDS_EDIT)")
):
    """
    저장된 분석 결과 목록 조회.
    쿼리 파라미터로 타입, 상태 필터링 가능.
    """
    if type:
        results = get_results_by_type(type)
    elif status:
        results = get_results_by_status(status)
    else:
        results = get_all_results()

    # fields가 JSON 문자열이므로 딕셔너리로 변환
    for r in results:
        if isinstance(r.get("fields"), str):
            try:
                r["fields"] = json.loads(r["fields"])
            except json.JSONDecodeError:
                r["fields"] = {}

    return results


@router.get("/{id}")
def get_result(id: int):
    """단건 결과 조회"""
    result = get_result_by_id(id)
    if not result:
        raise HTTPException(status_code=404, detail=f"결과 #{id}을(를) 찾을 수 없습니다")

    # fields JSON 파싱
    if isinstance(result.get("fields"), str):
        try:
            result["fields"] = json.loads(result["fields"])
        except json.JSONDecodeError:
            result["fields"] = {}

    return result


@router.put("/{id}")
def update_result(id: int, request: ResultConfirmRequest):
    """
    사용자가 초안 카드의 필드를 수정.
    수정 후 상태를 CONFIRMED로 변경.
    """
    existing = get_result_by_id(id)
    if not existing:
        raise HTTPException(status_code=404, detail=f"결과 #{id}을(를) 찾을 수 없습니다")

    if request.edited_fields:
        # 기존 fields에 수정 사항을 병합
        current_fields = {}
        if isinstance(existing.get("fields"), str):
            try:
                current_fields = json.loads(existing["fields"])
            except json.JSONDecodeError:
                current_fields = {}
        elif isinstance(existing.get("fields"), dict):
            current_fields = existing["fields"]

        # 수정된 필드 덮어쓰기 (기존 값 유지 + 변경분 반영)
        current_fields.update(request.edited_fields)
        update_fields(id, json.dumps(current_fields, ensure_ascii=False))

    # 수정 후 승인 처리
    update_status(id, "CONFIRMED")

    return {"message": f"결과 #{id}이(가) 수정 및 승인되었습니다"}


@router.post("/{id}/confirm")
def confirm_result(id: int):
    """결과 승인 (수정 없이 그대로 승인)"""
    existing = get_result_by_id(id)
    if not existing:
        raise HTTPException(status_code=404, detail=f"결과 #{id}을(를) 찾을 수 없습니다")

    update_status(id, "CONFIRMED")
    return {"message": f"결과 #{id}이(가) 승인되었습니다"}


@router.delete("/{id}")
def remove_result(id: int):
    """결과 삭제"""
    existing = get_result_by_id(id)
    if not existing:
        raise HTTPException(status_code=404, detail=f"결과 #{id}을(를) 찾을 수 없습니다")

    delete_result(id)
    return {"message": f"결과 #{id}이(가) 삭제되었습니다"}
```

### 3단계: schemas.py 보강

`ResultConfirmRequest`는 이미 있지만, 필요한 추가 스키마:

```python
# schemas.py에 추가

class ResultDetailResponse(BaseModel):
    """단건 결과 상세 응답"""
    id: int
    type: ScreenshotType
    confidence: float
    fields: dict
    status: str
    created_at: str | None = None
    updated_at: str | None = None
```

### /docs에서 테스트 시나리오

1. `POST /api/analyze/v2` — 서문시장 텍스트로 분석 → id 확인
2. `GET /api/results` — 목록 확인
3. `GET /api/results/{id}` — 단건 상세 확인
4. `PUT /api/results/{id}` — 필드 수정 + 승인
5. `GET /api/results?status=CONFIRMED` — 승인된 것만 조회
6. `DELETE /api/results/{id}` — 삭제

### ✅ Day 16 체크리스트
- [ ] `GET /api/results/{id}` — 단건 조회가 동작한다
- [ ] `PUT /api/results/{id}` — 필드 수정 + 승인이 동작한다
- [ ] `DELETE /api/results/{id}` — 삭제가 동작한다
- [ ] `GET /api/results?type=PLACE` — 타입 필터링이 동작한다
- [ ] `GET /api/results?status=CONFIRMED` — 상태 필터링이 동작한다
- [ ] 커밋: `feat: 결과 CRUD API 완성 (조회/수정/삭제/필터링)`

---

## Day 17 (수) — LLM 4종 통합 테스트 + 엣지 케이스 방어

> [!TIP]
> 오늘의 목표: 어떤 텍스트가 와도 서버가 안 죽고, 합리적인 결과를 반환하는지 확인

### 1단계: 종합 테스트 스크립트

`tests/test_all_types.py`를 만들어서 4종 타입별 + 엣지 케이스를 한 번에 테스트:

```python
# tests/test_all_types.py
import urllib.request
import json
import sys

BASE = "http://127.0.0.1:8000/api"

def call_api(ocr_text: str) -> dict:
    """분석 API 호출"""
    data = json.dumps({"ocr_text": ocr_text, "masked_tokens": []}).encode("utf-8")
    req = urllib.request.Request(
        f"{BASE}/analyze/v2",
        data=data,
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=30) as res:
        return json.loads(res.read().decode("utf-8"))

# ==================== 정상 케이스 ====================

test_cases = [
    {
        "name": "✅ 기프티콘 (SCHEDULE)",
        "ocr_text": "[기프티콘] 투썸플레이스 스트로베리 라떼\n유효기간: 2026.09.30\n교환처: 투썸플레이스 전 매장\n바코드: 1234-5678-9012",
        "expected_type": "SCHEDULE"
    },
    {
        "name": "✅ 맛집 1곳 (PLACE)",
        "ocr_text": "을지다락 ★4.5\n서울 중구 을지로 115\n영업시간 11:00-22:00\n한식, 분위기 좋은 식당\n추천: 된장찌개, 제육볶음",
        "expected_type": "PLACE"
    },
    {
        "name": "✅ 맛집 여러 곳 (PLACE — 복수)",
        "ocr_text": "🏠 1.재경사\n🍀 대구 중구 큰장로28길 38-5\n🏠 2.압구정아이\n🍀 서문시장 2지구 서나10호\n🏠 3.마포상사\n🍀 대구 중구 큰장로28길 10\n🏠 4.경신상회\n🍀 대구 중구 큰장로28길 39",
        "expected_type": "PLACE"
    },
    {
        "name": "✅ 쇼핑 (WISHLIST)",
        "ocr_text": "나이키 에어맥스 90\n129,000원 → 89,900원 (30% 할인)\n무신사 | 무료배송\n사이즈: 270\n색상: 블랙/화이트",
        "expected_type": "WISHLIST"
    },
    {
        "name": "✅ 메모 (MEMO)",
        "ocr_text": "하루 물 2리터 마시기의 효과\n1. 피부 개선\n2. 신진대사 촉진\n3. 두통 예방\n- 출처: 헬스조선 2026.06.15",
        "expected_type": "MEMO"
    },
]

# ==================== 엣지 케이스 ====================

edge_cases = [
    {
        "name": "⚡ 빈 텍스트",
        "ocr_text": "",
        "check": lambda r: r.get("type") is not None  # 어떤 타입이든 반환
    },
    {
        "name": "⚡ 매우 짧은 텍스트",
        "ocr_text": "안녕",
        "check": lambda r: r.get("type") is not None
    },
    {
        "name": "⚡ 특수문자만",
        "ocr_text": "!!@#$%^&*()\n🎉🎊🥳",
        "check": lambda r: r.get("type") is not None
    },
    {
        "name": "⚡ 애매한 케이스 (일정+장소)",
        "ocr_text": "강남역 스타벅스에서 3시에 만나자\n토요일 오후 3시\n강남역 10번 출구 앞",
        "check": lambda r: r.get("type") in ("SCHEDULE", "PLACE")  # 둘 다 합리적
    },
    {
        "name": "⚡ 카카오톡 대화",
        "ocr_text": "지현: 이번 주 토요일 2시에 보자\n나: 어디서?\n지현: 홍대 카페 어때?\n나: 좋아 어디?\n지현: 연남동 카페꼼마 ㅎㅎ\n나: ㅋㅋ 거기 맛있어?",
        "check": lambda r: r.get("type") in ("SCHEDULE", "PLACE")
    },
]

# ==================== 실행 ====================

print("=" * 60)
print("🧪 소생 앱 API 종합 테스트")
print("=" * 60)

success = 0
fail = 0

# 정상 케이스
print("\n📋 정상 케이스:")
for tc in test_cases:
    try:
        result = call_api(tc["ocr_text"])
        is_match = result["type"] == tc["expected_type"]
        icon = "✅" if is_match else "❌"
        print(f"  {icon} [{tc['name']}]")
        print(f"     예상: {tc['expected_type']} → 결과: {result['type']} (신뢰도: {result['confidence']})")

        # 복수 항목 체크
        fields = result.get("fields", {})
        if "items" in fields:
            print(f"     📦 {len(fields['items'])}개 항목 추출됨")

        print(f"     상태: {result['status']} | 누락: {result.get('missing_fields', [])}")

        if is_match:
            success += 1
        else:
            fail += 1
    except Exception as e:
        print(f"  💥 [{tc['name']}] 에러: {e}")
        fail += 1

# 엣지 케이스
print("\n⚡ 엣지 케이스:")
for ec in edge_cases:
    try:
        result = call_api(ec["ocr_text"])
        passed = ec["check"](result)
        icon = "✅" if passed else "❌"
        print(f"  {icon} [{ec['name']}]")
        print(f"     결과: {result['type']} (신뢰도: {result['confidence']}) 상태: {result['status']}")

        if passed:
            success += 1
        else:
            fail += 1
    except Exception as e:
        print(f"  💥 [{ec['name']}] 에러: {e}")
        fail += 1

# 결과 요약
print("\n" + "=" * 60)
print(f"📊 결과: {success}개 성공 / {fail}개 실패 / 총 {success + fail}개")
print("=" * 60)

if fail > 0:
    sys.exit(1)
```

실행:
```powershell
# 서버 실행 중인 상태에서 다른 터미널에서:
python tests/test_all_types.py
```

### 2단계: 빈 텍스트 / 초짧은 텍스트 방어

`app/routers/analyze.py`에 입력 검증을 추가하세요:

```python
@router.post("/analyze/v2", response_model=AnalyzeResponse)
def analyze_v2(request: AnalyzeRequest):
    """2단계 분석: 분류 → 타입별 상세 추출"""

    # 🛡️ 입력 검증: 너무 짧은 텍스트
    clean_text = request.ocr_text.strip()
    if len(clean_text) < 3:
        return AnalyzeResponse(
            id=None,
            type="MEMO",
            confidence=0.0,
            fields={"body": clean_text} if clean_text else {},
            missing_fields=["텍스트가 너무 짧습니다 (3자 이상 필요)"],
            status="NEEDS_EDIT"
        )

    # 🛡️ 입력 검증: 너무 긴 텍스트 (LLM 토큰 제한 방지)
    if len(clean_text) > 5000:
        clean_text = clean_text[:5000]
        request.ocr_text = clean_text

    # === 1단계: 분류 === (이하 기존 코드 동일)
    ...
```

### ✅ Day 17 체크리스트
- [ ] 5개 정상 케이스 테스트 중 4개 이상 통과
- [ ] 5개 엣지 케이스 테스트 중 4개 이상 통과 (서버가 안 죽음)
- [ ] 빈 텍스트를 보내도 500 에러 없이 정상 응답이 온다
- [ ] 매우 긴 텍스트를 보내도 타임아웃 없이 처리된다
- [ ] 커밋: `test: 4종 통합 테스트 + 엣지 케이스 방어 로직`

---

## Day 18 (목) — 검증 레이어 v2 + 사용자 수정 반영

> [!TIP]
> 오늘의 목표: 사용자가 초안 카드를 수정하면, 그 결과를 반영하고 재검증하는 로직 완성

### 1단계: validator.py v2 업그레이드

현재 `validator.py`는 잘 동작하지만, **사용자 수정 후 재검증** 기능이 없어요.

`app/validator.py`에 재검증 함수 추가:

```python
def revalidate_after_edit(result: dict, edited_fields: dict) -> dict:
    """
    사용자가 수정한 필드를 반영하고 다시 검증.
    수정 후에는 누락 필드가 채워졌을 수 있으므로 상태를 재판단.
    """
    # 기존 필드에 수정 사항 병합
    current_fields = result.get("fields", {})

    if "items" in current_fields and isinstance(current_fields["items"], list):
        # 복수 항목인 경우: edited_fields에 items가 있으면 그대로 교체
        if "items" in edited_fields:
            current_fields["items"] = edited_fields["items"]
        else:
            # items가 아닌 경우, 각 항목에 공통 수정 적용
            for item in current_fields["items"]:
                item.update(edited_fields)
    else:
        # 단일 항목인 경우: 바로 덮어쓰기
        current_fields.update(edited_fields)

    result["fields"] = current_fields

    # 재검증
    return validate_result(result)
```

### 2단계: PUT /api/results/{id} 에서 재검증 적용

`app/routers/results.py`의 `update_result` 함수를 개선:

```python
from app.validator import validate_result, revalidate_after_edit

@router.put("/{id}")
def update_result(id: int, request: ResultConfirmRequest):
    """
    사용자가 초안 카드의 필드를 수정.
    재검증 후 상태를 자동 결정 (DRAFT / NEEDS_EDIT / CONFIRMED).
    """
    existing = get_result_by_id(id)
    if not existing:
        raise HTTPException(status_code=404, detail=f"결과 #{id}을(를) 찾을 수 없습니다")

    if request.edited_fields:
        # 기존 결과 복원
        current_fields = {}
        if isinstance(existing.get("fields"), str):
            try:
                current_fields = json.loads(existing["fields"])
            except json.JSONDecodeError:
                current_fields = {}

        # 재검증 실행
        result_for_validate = {
            "type": existing["type"],
            "confidence": existing["confidence"],
            "fields": current_fields
        }
        validated = revalidate_after_edit(result_for_validate, request.edited_fields)

        # DB 업데이트
        update_fields(id, json.dumps(validated["fields"], ensure_ascii=False))

        # 검증 통과하면 CONFIRMED, 아니면 validator가 정한 상태
        if not validated.get("missing_fields"):
            update_status(id, "CONFIRMED")
        else:
            update_status(id, validated.get("status", "NEEDS_EDIT"))

        return {
            "message": f"결과 #{id} 수정 완료",
            "status": validated.get("status", "CONFIRMED"),
            "missing_fields": validated.get("missing_fields", [])
        }

    # 수정 없이 승인만
    update_status(id, "CONFIRMED")
    return {"message": f"결과 #{id}이(가) 승인되었습니다", "status": "CONFIRMED"}
```

### 3단계: 테스트 시나리오

`/docs`에서 이 흐름을 테스트하세요:

```
1. POST /api/analyze/v2 → 기프티콘 텍스트 (유효기간 누락)
   → status: "NEEDS_EDIT", missing_fields: ["expires_at 또는 start_at"]

2. PUT /api/results/{id} → edited_fields: {"expires_at": "2026-12-31"}
   → status: "CONFIRMED", missing_fields: []

3. GET /api/results/{id} → fields에 expires_at이 추가되어 있는지 확인
```

### ✅ Day 18 체크리스트
- [ ] `NEEDS_EDIT` 상태인 결과를 수정하면 `CONFIRMED`로 바뀐다
- [ ] 수정 후에도 필수 필드가 누락되면 여전히 `NEEDS_EDIT` 상태다
- [ ] 복수 항목(items)의 수정도 정상 동작한다
- [ ] 커밋: `feat: 검증 레이어 v2 + 사용자 수정 재검증`

---

## Day 19 (금) — 서버 ↔ Flutter 앱 통합 테스트

> [!IMPORTANT]
> 오늘은 공다은과 **실시간으로 함께** 테스트해야 해요!

### 1단계: 서버 안정화 점검

통합 테스트 전에 서버가 안정적인지 최종 점검:

```powershell
# 서버 시작
python run.py

# 다른 터미널에서 종합 테스트
python tests/test_all_types.py
```

### 2단계: Flutter 앱과 연동 테스트 체크리스트

공다은과 함께 아래 시나리오를 순서대로 테스트:

```
[ 시나리오 1: 기본 흐름 ]
1. 앱에서 이미지 선택
2. OCR 결과가 서버로 전송됨
3. 서버가 분류 + 구조화 결과를 반환
4. 앱에서 초안 카드가 표시됨

[ 시나리오 2: 승인 흐름 ]
5. 초안 카드에서 "승인" 버튼 클릭
6. POST /api/results/{id}/confirm 호출 확인
7. 상태가 CONFIRMED로 변경됨

[ 시나리오 3: 수정 흐름 ]
8. 초안 카드에서 필드 수정
9. PUT /api/results/{id} 호출 확인
10. 수정된 내용이 반영됨

[ 시나리오 4: 삭제 흐름 ]
11. 초안 카드에서 "삭제" 클릭
12. DELETE /api/results/{id} 호출 확인
13. 목록에서 사라짐

[ 시나리오 5: 에러 대응 ]
14. 서버를 끄고 앱에서 요청 → 앱이 크래시 없이 에러 메시지 표시
15. 서버 다시 켜고 재요청 → 정상 동작
```

### 3단계: 통합 이슈 대응

자주 발생하는 문제와 해결 방법:

| 문제 | 원인 | 해결 |
|------|------|------|
| 앱에서 `Connection refused` | 서버가 안 켜져 있음 / IP 주소 잘못됨 | `python run.py` 확인, `ipconfig`로 IP 재확인 |
| CORS 에러 | `CORSMiddleware` 미설정 | Day 15 코드 확인 |
| `422 Unprocessable Entity` | 요청 형식이 다름 (필드명 오타 등) | `/docs`에서 올바른 형식 확인 후 공다은에게 공유 |
| 응답이 너무 느림 (10초+) | LLM 호출 2번이라 오래 걸림 | 서버 로그에서 어디서 막히는지 확인 |
| `fields`가 문자열로 옴 | DB에서 JSON을 문자열로 저장함 | `results.py`에서 `json.loads()` 처리 확인 |

### 4단계: 서버 로그에서 디버깅

문제 발생 시 서버 터미널에 찍히는 로그를 확인하세요:

```
INFO:     127.0.0.1:52341 - "POST /api/analyze/v2 HTTP/1.1" 200 OK
INFO:app.routers.analyze:[v2] 분류: PLACE | GPT 추출 원본: {"fields": [...]}
INFO:app.llm_client:LLM 호출 성공 (시도 1)
```

로그가 잘 안 보이면 `run.py`에 로깅 설정 추가:

```python
import uvicorn
import logging

# 로그 레벨 설정 — 디버깅용
logging.basicConfig(level=logging.INFO)

if __name__ == "__main__":
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
```

### ✅ Day 19 체크리스트
- [ ] Flutter 앱에서 서버로 텍스트 전송이 성공한다
- [ ] 서버 응답이 앱에 초안 카드로 정상 표시된다
- [ ] 승인/수정/삭제 전체 흐름이 동작한다
- [ ] 서버 꺼짐 → 앱에서 에러 처리 → 서버 재시작 → 복구 확인
- [ ] 커밋: `feat: 서버-앱 통합 테스트 완료`

---

## Day 20~21 (주말) — End-to-End 데모 준비 + 팀 리허설

### Day 20: 데모 시나리오 확정 + 데이터 준비

#### 데모 시나리오 (5분 시연용)

4개 타입 각각을 보여줄 수 있는 데모 시나리오를 준비하세요:

```
🎬 시나리오 1: 기프티콘 유효기간 관리 (SCHEDULE)
- 스타벅스 기프티콘 스크린샷 → 자동 추출 → "D-23 남았어요!" 표시 → 승인

🎬 시나리오 2: 맛집 리스트 저장 (PLACE)
- 인스타그램 맛집 추천 게시물 → 4개 장소 자동 추출 → 카드 확인 → 승인

🎬 시나리오 3: 쇼핑 위시리스트 (WISHLIST)
- 쿠팡 장바구니 캡처 → 상품명/가격 자동 추출 → 할인율 표시 → 승인

🎬 시나리오 4: 레시피 메모 (MEMO)
- 요리 레시피 블로그 캡처 → 재료/순서 자동 구조화 → 승인
```

#### 데모용 OCR 텍스트 준비

실제 스크린샷 OCR이 아직 불안정할 수 있으니, **미리 준비한 텍스트**로 데모하는 게 안전:

```python
# tests/demo_data.py — 데모용 샘플 데이터

DEMO_SCHEDULE = """[기프티콘] 스타벅스 아이스 아메리카노 T
유효기간: 2026.08.15까지
교환처: 스타벅스 전 매장
주문번호: GFT-2026-0812-4421
바코드: {MASKED_CARD}"""

DEMO_PLACE = """🏠 서문시장 맛집 리스트

🏠 1.재경사
🍀 대구 중구 큰장로28길 38-5
⭐ 크런치 메뉴가 유명!

🏠 2.압구정아이
🍀 서문시장 2지구 서나10호

🏠 3.마포상사
🍀 대구 중구 큰장로28길 10

🏠 4.경신상회
🍀 대구 중구 큰장로28길 39

#서문시장맛집 #대구맛집 #대구핫플"""

DEMO_WISHLIST = """나이키 에어맥스 90
정가: 179,000원
할인가: 129,000원 (28% OFF)
사이즈: 270
색상: 블랙/화이트
무신사 | 무료배송 | 리뷰 2,341개 ★4.3"""

DEMO_MEMO = """🍳 간장계란밥 레시피

재료: 밥 1공기, 계란 2개, 간장 2T, 참기름 1T, 김가루, 쪽파

1. 팬에 기름 두르고 계란 2개 프라이
2. 밥 위에 계란 올리기
3. 간장 2T + 참기름 1T 뿌리기
4. 김가루 + 쪽파 토핑
5. 비벼서 먹기!

출처: @home_cook_recipe"""
```

### Day 21: 팀 리허설

#### 리허설 체크리스트

```
[ ] 서버가 안정적으로 실행된다 (재시작 없이 5분 이상)
[ ] 4개 시나리오를 순서대로 시연할 수 있다
[ ] 각 시나리오에서 분류 → 추출 → 카드 표시 → 승인까지 5초 이내
[ ] 에러 상황 발생 시 앱이 크래시 없이 대응한다
[ ] 팀원 모두 각자 맡은 파트를 설명할 수 있다
```

#### 역할 분담 (시연 시)

| 파트 | 담당 | 설명 내용 |
|------|------|----------|
| 전체 흐름 설명 | 정채윤 | 8단계 파이프라인 아키텍처, On-device AI 분류 |
| 앱 시연 | 공다은 | 이미지 업로드 → OCR → 초안 카드 UI 시연 |
| 서버 동작 설명 | 오예린 | 2단계 LLM 분석, 검증 레이어, API 구조 |

### ✅ Day 20~21 체크리스트
- [ ] 데모용 OCR 텍스트 4종이 준비되었다
- [ ] 4개 시나리오를 순서대로 시연할 수 있다
- [ ] 전체 파이프라인이 **1장의 이미지 기준 5초 이내**로 처리된다
- [ ] 팀 리허설을 1회 이상 진행했다
- [ ] 모든 코드가 커밋 + 푸시되었다
- [ ] 커밋: `feat: 3주차 완료 - End-to-End 파이프라인 데모`

---

## 📊 3주차 끝나면 이런 상태!

```
Week 2:
app/
├── main.py          ← 앱 진입점
├── config.py        ← 설정 관리
├── schemas.py       ← 데이터 형식
├── prompts.py       ← 4종 전용 프롬프트
├── database.py      ← DB 관리
├── validator.py     ← 검증 레이어
├── llm_client.py    ← 안전한 LLM 호출
└── routers/
    ├── analyze.py   ← 분석 API (v1 + v2)
    └── results.py   ← 결과 조회/승인 API
         ↓
Week 3: ⭐ 업그레이드 ⭐
app/
├── main.py          ← + CORS 설정 🆕
├── config.py        ← (동일)
├── schemas.py       ← + ResultDetailResponse 🆕
├── prompts.py       ← (동일, 이미 보강 완료)
├── database.py      ← + 수정/삭제/필터링 함수 🆕
├── validator.py     ← + revalidate_after_edit() 🆕
├── llm_client.py    ← (동일)
└── routers/
    ├── analyze.py   ← + 입력 검증 (짧은/긴 텍스트 방어) 🆕
    └── results.py   ← 풀 CRUD (조회/수정/삭제/필터링) 🆕
tests/
    ├── test_analyze.py      ← (기존)
    ├── test_all_types.py    ← 4종 통합 + 엣지 케이스 🆕
    └── demo_data.py         ← 데모용 샘플 데이터 🆕
```

### 기능 비교: Week 2 vs Week 3

| 기능 | Week 2 | Week 3 |
|------|--------|--------|
| 분석 API | ✅ v1 + v2 | ✅ + 입력 검증 추가 |
| 결과 조회 | 전체 목록만 | ✅ 단건/타입별/상태별 필터 |
| 결과 수정 | ❌ | ✅ 필드 수정 + 재검증 |
| 결과 삭제 | ❌ | ✅ |
| 결과 승인 | ✅ | ✅ + 재검증 후 자동 상태 결정 |
| CORS | ❌ | ✅ Flutter 앱 연동 가능 |
| 앱 연동 | ❌ | ✅ End-to-End 테스트 완료 |
| 통합 테스트 | 4개 케이스 | ✅ 10개+ (정상 + 엣지) |

---

## 🔮 4주차 미리보기

> [!IMPORTANT]
> **4주차**: SCHEDULE + WISHLIST 타입에 집중해서 **기능 v1 병렬 개발**을 시작합니다.
> - SCHEDULE: 만료일 자동 계산, D-day 표시, 알림 추천 고도화
> - WISHLIST: 가격 비교, 할인율 계산, 카테고리 자동 태깅
> - DB 스키마를 타입별로 최적화 (현재 하나의 `screenshots` 테이블 → 타입별 분리 검토)
> - 프롬프트 정밀 튜닝 (실제 사용 데이터로 테스트 → 프롬프트 개선)

---

> [!TIP]
> **3주차의 핵심**: 혼자 만든 서버를 **팀과 연결**하는 것! 코드를 새로 많이 짜기보다, **기존 코드를 안정화하고, 앱과 연동하고, 데모를 준비**하는 데 집중하세요. 🤝
