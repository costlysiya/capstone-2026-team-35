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