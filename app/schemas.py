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
    ical_string: str | None = None

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

class TokenRequest(BaseModel):
    device_token: str

class NotificationResponse(BaseModel):
    id: int
    title: str
    body: str
    result_id: int | None
    is_read: bool
    created_at: str

# === LLM Structured Outputs (json_schema) ===
from pydantic import Field

class LLMClassifyResponse(BaseModel):
    type: str = Field(description="SCHEDULE, PLACE, WISHLIST, MEMO 중 하나")
    confidence: float = Field(description="분류 신뢰도 0.0~1.0")

class LLMScheduleItem(BaseModel):
    title: str = Field(description="일정/기프티콘/예약 이름")
    expires_at: str | None = Field(None, description="만료일/종료일 YYYY-MM-DD")
    start_at: str | None = Field(None, description="시작일/예약일/출발일 YYYY-MM-DD")
    start_time: str | None = Field(None, description="시작 시각 HH:MM")
    end_time: str | None = Field(None, description="종료 시각 HH:MM")
    reminder_days: list[int] | None = Field(None, description="알림 추천 일수 리스트")
    exchange_place: str | None = Field(None, description="교환처/장소")
    participants: list[str] | None = Field(None, description="참여자")
    recurrence: str | None = Field(None, description="반복 주기")
    cancellation_deadline: str | None = Field(None, description="취소/환불 마감일시 YYYY-MM-DD HH:MM")
    sub_type: str | None = Field(None, description="GIFTICON, APPOINTMENT, TICKET, SUBSCRIPTION, DEADLINE, DELIVERY 중 하나")

class LLMScheduleResponse(BaseModel):
    fields: list[LLMScheduleItem]
    missing_fields: list[str]

class LLMPlaceItem(BaseModel):
    name: str = Field(description="장소/식당 이름")
    region: str | None = Field(None, description="지역명")
    address: str | None = Field(None, description="상세 주소")
    category: str | None = Field(None, description="카테고리")
    rating: str | None = Field(None, description="별점/평점")
    opening_hours: str | None = Field(None, description="영업시간")

class LLMPlaceResponse(BaseModel):
    fields: list[LLMPlaceItem]
    missing_fields: list[str]

class LLMWishlistItem(BaseModel):
    product_name: str = Field(description="상품 이름")
    price_amount: str | None = Field(None, description="가격 숫자")
    option: str | None = Field(None, description="선택 옵션")
    store_name: str | None = Field(None, description="판매처 이름")
    url: str | None = Field(None, description="URL")

class LLMWishlistResponse(BaseModel):
    fields: list[LLMWishlistItem]
    missing_fields: list[str]

class LLMIngredient(BaseModel):
    name: str = Field(description="재료 이름")
    amount: str | None = Field(None, description="수량")

class LLMChecklistItem(BaseModel):
    text: str = Field(description="항목 내용")
    checked: bool = Field(description="완료 여부")

class LLMMemoItem(BaseModel):
    body: str = Field(description="핵심 내용")
    sub_type: str = Field(description="RECIPE, NOVEL, CHECKLIST, ARTICLE, NOTE, OTHER 중 하나")
    title: str | None = Field(None, description="제목")
    source: str | None = Field(None, description="출처")
    date: str | None = Field(None, description="날짜 YYYY-MM-DD")
    url: str | None = Field(None, description="URL")
    
    recipe_name: str | None = Field(None, description="요리 이름")
    ingredients: list[LLMIngredient] | None = Field(None, description="재료 리스트")
    steps: list[str] | None = Field(None, description="조리 순서")
    servings: str | None = Field(None, description="인분")
    cook_time: str | None = Field(None, description="조리 시간")
    
    book_title: str | None = Field(None, description="책 제목")
    author: str | None = Field(None, description="작가명")
    platform: str | None = Field(None, description="플랫폼")
    chapter: str | None = Field(None, description="회차")
    genre: str | None = Field(None, description="장르")
    excerpt: str | None = Field(None, description="발췌 원문")
    
    checklist_items: list[LLMChecklistItem] | None = Field(None, description="할 일 목록")
    total_count: int | None = Field(None, description="총 개수")
    checked_count: int | None = Field(None, description="완료 개수")
    
    headline: str | None = Field(None, description="기사 제목")
    publisher: str | None = Field(None, description="작성자")
    published_at: str | None = Field(None, description="발행일")

class LLMMemoResponse(BaseModel):
    fields: list[LLMMemoItem]
    missing_fields: list[str]

# === Bulk Processing Schemas ===
class LLMBulkClassifyItem(BaseModel):
    index: int = Field(description="제공된 텍스트의 인덱스 번호")
    type: str = Field(description="SCHEDULE, PLACE, WISHLIST, MEMO 중 하나")
    confidence: float = Field(description="분류 신뢰도 0.0~1.0")

class LLMBulkClassifyResponse(BaseModel):
    results: list[LLMBulkClassifyItem]

class LLMBulkScheduleItemResponse(BaseModel):
    index: int = Field(description="제공된 텍스트의 인덱스 번호")
    fields: list[LLMScheduleItem]
    missing_fields: list[str]

class LLMBulkScheduleResponse(BaseModel):
    results: list[LLMBulkScheduleItemResponse]

class LLMBulkPlaceItemResponse(BaseModel):
    index: int = Field(description="제공된 텍스트의 인덱스 번호")
    fields: list[LLMPlaceItem]
    missing_fields: list[str]

class LLMBulkPlaceResponse(BaseModel):
    results: list[LLMBulkPlaceItemResponse]

class LLMBulkWishlistItemResponse(BaseModel):
    index: int = Field(description="제공된 텍스트의 인덱스 번호")
    fields: list[LLMWishlistItem]
    missing_fields: list[str]

class LLMBulkWishlistResponse(BaseModel):
    results: list[LLMBulkWishlistItemResponse]

class LLMBulkMemoItemResponse(BaseModel):
    index: int = Field(description="제공된 텍스트의 인덱스 번호")
    fields: list[LLMMemoItem]
    missing_fields: list[str]

class LLMBulkMemoResponse(BaseModel):
    results: list[LLMBulkMemoItemResponse]