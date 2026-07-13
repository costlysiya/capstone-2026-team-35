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

    class Config:
        json_schema_extra = {
            "example": {
                "ocr_text": "[기프티콘] 스타벅스 아메리카노\n유효기간: 2026.08.15",
                "type": "SCHEDULE",
                "masked_tokens": []
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

class ResultDetailResponse(BaseModel):
    """단건 결과 상세 응답"""
    id: int
    type: ScreenshotType
    confidence: float
    fields: dict
    status: str
    created_at: str | None = None
    updated_at: str | None = None