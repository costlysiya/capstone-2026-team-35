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
    type: ScreenshotType | None = None  # 앱에서 로컬 분류한 타입 (없으면 서버가 LLM으로 분류)
    masked_tokens: list[str] = []
    image_hash: str | None = None  # 이미지 SHA-256 해시 (중복 분석 방지용)

    class Config:
        json_schema_extra = {
            "example": {
                "ocr_text": "[기프티콘] 스타벅스 아메리카노\n유효기간: 2026.08.15",
                "type": "SCHEDULE",
                "masked_tokens": [],
                "image_hash": "a1b2c3d4e5f6..."
            }
        }

class ClassifyResponse(BaseModel):
    """분류 전용 결과 응답"""
    index: int
    type: str
    confidence: float
    reasoning: str

class AnalyzeResponse(BaseModel):
    """서버 → 앱 응답"""
    id: int | None = None
    type: ScreenshotType
    confidence: float
    fields: dict
    missing_fields: list[str] = []
    status: str = "DRAFT"
    masked_info: list[dict] = []  # 앱에서 마스킹해서 보낸 원본 토큰의 구조화된 정보

class ResultConfirmRequest(BaseModel):
    """사용자 승인 요청"""
    edited_fields: dict | None = None  # 수정된 필드 (있으면)

class ResultDetailResponse(BaseModel):
    """단건 결과 상세 응답"""
    id: int
    type: ScreenshotType
    confidence: float
    fields: dict
    status: str
    created_at: str | None = None
    updated_at: str | None = None

class BatchAnalyzeRequest(BaseModel):
    """배치 분석 요청 — 복수 이미지를 한 번에"""
    items: list[AnalyzeRequest]  # 최대 20개까지

    class Config:
        json_schema_extra = {
            "example": {
                "items": [
                    {"ocr_text": "[기프티콘] 스타벅스 아메리카노\n유효기간: 2026.08.15", "type": "SCHEDULE", "masked_tokens": []},
                    {"ocr_text": "을지다락 ★4.5\n서울 중구 을지로 115", "type": "PLACE", "masked_tokens": []}
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
class BatchClassifyResponse(BaseModel):
    """묶음 분류 전용 응답"""
    total: int
    results: list[ClassifyResponse]

class BatchAsyncResponse(BaseModel):
    """비동기 배치 분석 접수 응답"""
    task_id: str
    status: str = "PENDING"
    message: str = "배치 작업이 백그라운드 큐에 등록되었습니다."

class BatchStatusResponse(BaseModel):
    """비동기 배치 작업 상태 응답"""
    task_id: str
    status: str  # PENDING, PROCESSING, COMPLETED, ERROR
    total: int
    completed: int
    failed: int
    results: list[AnalyzeResponse] = []
    errors: list[dict] = []