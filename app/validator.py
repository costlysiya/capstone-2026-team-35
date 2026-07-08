# validator.py

REQUIRED_FIELDS = {
    "SCHEDULE": ["title"],           # + expires_at 또는 start_at 중 하나
    "PLACE":    [],                   # name 또는 region 중 하나
    "WISHLIST": ["product_name"],     # price_amount는 없을 수도 있으므로 선택
    "MEMO":     ["body"]
}

VALID_TYPES = {"SCHEDULE", "PLACE", "WISHLIST", "MEMO"}


def _get_validate_targets(fields: dict) -> list[dict]:
    """
    fields가 단일 항목이면 [fields]로,
    복수 항목(items 리스트)이면 그 리스트를 반환.
    → 검증 로직을 단일/복수 구분 없이 동일하게 적용하기 위함.
    """
    if "items" in fields and isinstance(fields["items"], list):
        return fields["items"]
    return [fields]


def _validate_single_item(item: dict, result_type: str) -> list[str]:
    """단일 항목에 대해 필수 필드 검증, 누락된 필드명 리스트를 반환"""
    missing = []

    # 공통 필수 필드 검증
    for req_field in REQUIRED_FIELDS.get(result_type, []):
        if req_field not in item or not item[req_field]:
            missing.append(req_field)

    # 타입별 특수 검증
    if result_type == "SCHEDULE":
        if "expires_at" not in item and "start_at" not in item:
            missing.append("expires_at 또는 start_at")

    if result_type == "PLACE":
        if "name" not in item and "region" not in item:
            missing.append("name 또는 region")

    return missing


def validate_result(result: dict) -> dict:
    """
    LLM 응답을 검증하고 부족한 부분을 표시.
    단일 항목(fields: {...})과 복수 항목(fields: {items: [...]}) 모두 지원.
    """
    # 1) 타입 검증
    result_type = result.get("type", "")
    if result_type not in VALID_TYPES:
        result["type"] = "MEMO"  # 기본값으로 폴백

    # 2) 신뢰도 검증
    confidence = result.get("confidence", 0)
    if not (0 <= confidence <= 1):
        result["confidence"] = max(0, min(1, confidence))

    # 3) 필수 필드 검증 — 단일/복수 항목 모두 처리
    fields = result.get("fields", {})
    targets = _get_validate_targets(fields)

    all_missing = []
    for idx, item in enumerate(targets):
        item_missing = _validate_single_item(item, result["type"])
        if item_missing:
            if len(targets) > 1:
                # 복수 항목이면 몇 번째에서 누락됐는지 표시
                all_missing.extend([f"[항목{idx+1}] {m}" for m in item_missing])
            else:
                all_missing.extend(item_missing)

    result["missing_fields"] = all_missing

    # 4) 상태 결정
    if all_missing:
        result["status"] = "NEEDS_EDIT"      # 수정 필요
    elif confidence < 0.7:
        result["status"] = "LOW_CONFIDENCE"  # 신뢰도 낮음
    else:
        result["status"] = "DRAFT"           # 정상 초안

    return result