# validator.py

REQUIRED_FIELDS = {
    "SCHEDULE": ["title"],           # + expires_at 또는 start_at 중 하나
    "PLACE":    [],                   # name 또는 region 중 하나
    "WISHLIST": ["product_name"],     # price_amount는 없을 수도 있으므로 선택
    "MEMO":     ["body"]
}

VALID_TYPES = {"SCHEDULE", "PLACE", "WISHLIST", "MEMO"}


def _get_validate_targets(fields: dict, result_type: str = "") -> list[dict]:
    """Return fields as a list for uniform validation."""
    if result_type == "MEMO":
        return [fields]
    if "items" in fields and isinstance(fields["items"], list):
        return fields["items"]
    return [fields]


def _validate_single_item(item: dict, result_type: str) -> list[str]:
    """Validate required fields and return missing field names."""
    missing = []

    # 공통 필수 필드 검증
    for req_field in REQUIRED_FIELDS.get(result_type, []):
        if req_field not in item or not item[req_field]:
            missing.append(req_field)

    # 타입별 특수 검증
    if result_type == "SCHEDULE":
        if not item.get("expires_at") and not item.get("start_at"):
            missing.append("expires_at 또는 start_at")

    if result_type == "PLACE":
        if not item.get("name") and not item.get("region"):
            missing.append("name 또는 region")

    return missing


def _enrich_schedule_fields(fields: dict) -> dict:
    """Enrich SCHEDULE fields based on sub_type."""
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
        # LLM이 null로 반환했을 수 있으므로 setdefault 대신 직접 확인
        if not fields.get("recurrence"):
            fields["recurrence"] = "매월"

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


def _enrich_place_fields(fields: dict) -> dict:
    """Enrich PLACE fields for map integration."""
    fields.setdefault("keep_photo", False)      # 장소는 사진 불필요
    fields.setdefault("map_ready", bool(fields.get("address") or fields.get("region")))
    # category 정규화 (없으면 "기타")
    fields.setdefault("category", "기타")
    return fields


def _enrich_wishlist_fields(fields: dict) -> dict:
    """Enrich WISHLIST fields."""
    fields.setdefault("keep_photo", True)       # 상품 원본 이미지 보관
    # 가격 정규화: 문자열이면 숫자만 추출
    price = fields.get("price_amount")
    if isinstance(price, str):
        import re
        nums = re.sub(r'[^\d.]', '', price)
        fields["price_amount"] = float(nums) if nums else None
    return fields


def _enrich_memo_fields(fields: dict) -> dict:
    """Enrich MEMO fields."""
    fields.setdefault("keep_photo", False)       # 메모는 사진 삭제
    
    sub_type = fields.get("sub_type", "")
    
    # Sub-type title overriding
    if sub_type == "NOVEL" and fields.get("book_title"):
        fields["title"] = fields["book_title"]
    elif sub_type == "RECIPE" and fields.get("recipe_name"):
        fields["title"] = fields["recipe_name"]
    elif sub_type == "ARTICLE" and fields.get("headline"):
        fields["title"] = fields["headline"]
    elif sub_type == "QR_CODE" and fields.get("label"):
        fields["title"] = fields["label"]
    elif not fields.get("title"):
        # sub_type 매칭이 안 되었고 title도 비어있을 때만 폴백
        if fields.get("book_title"):
            fields["title"] = fields["book_title"]
        elif fields.get("recipe_name"):
            fields["title"] = fields["recipe_name"]
        elif fields.get("headline"):
            fields["title"] = fields["headline"]
        elif fields.get("label"):
            fields["title"] = fields["label"]
        elif fields.get("body"):
            body = fields["body"]
            fields["title"] = body[:30] + ("..." if len(body) > 30 else "")
    
    # Rename items to checklist_items to avoid conflicts
    if sub_type == "CHECKLIST" and "items" in fields:
        fields["checklist_items"] = fields.pop("items")
            
    return fields


def validate_result(result: dict) -> dict:
    """Validate LLM response and mark missing fields."""
    # Type validation
    result_type = result.get("type", "")
    if result_type not in VALID_TYPES:
        result["type"] = "MEMO"  # 기본값으로 폴백

    # Confidence validation
    confidence = result.get("confidence", 0)
    if not (0 <= confidence <= 1):
        result["confidence"] = max(0, min(1, confidence))

    # Required field validation
    fields = result.get("fields", {})
    targets = _get_validate_targets(fields, result_type=result["type"])

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

    # Enrich fields based on type
    rtype = result["type"]
    for item in targets:
        if rtype == "SCHEDULE":
            _enrich_schedule_fields(item)
        elif rtype == "PLACE":
            _enrich_place_fields(item)
        elif rtype == "WISHLIST":
            _enrich_wishlist_fields(item)
        elif rtype == "MEMO":
            _enrich_memo_fields(item)

    # Determine status
    if all_missing:
        result["status"] = "NEEDS_EDIT"
    elif confidence < 0.7:
        result["status"] = "LOW_CONFIDENCE"
    else:
        result["status"] = "DRAFT"

    return result


def revalidate_after_edit(result: dict, edited_fields: dict) -> dict:
    """Merge user edits and revalidate."""
    # Merge updates
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

    return validate_result(result)