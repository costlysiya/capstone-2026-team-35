from fastapi import APIRouter, HTTPException
from app.schemas import AnalyzeRequest, AnalyzeResponse, BatchAnalyzeRequest, BatchAnalyzeResponse
from app.prompts import get_system_prompt, CLASSIFY_PROMPT, get_type_prompt
from app.validator import validate_result
from app.database import save_result, get_result_by_hash
from app.llm_client import call_llm
from app.concurrency import call_llm_with_limit
import json
import logging
import re

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["분석"])


def _extract_fields(raw: dict) -> dict:
    """
    GPT 응답에서 fields 데이터를 안전하게 꺼내는 함수.
    GPT는 응답 형식을 맘대로 바꾸기 때문에 여러 케이스를 처리한다.
    """
    # 케이스 1: 정상적으로 "fields" 키가 있는 경우
    if "fields" in raw:
        fields = raw["fields"]
        if isinstance(fields, list):
            return {"items": fields}
        if isinstance(fields, dict):
            return fields
        return {}

    # 케이스 2: "places", "items", "results", "products" 등 대체 키
    alt_keys = ["places", "items", "results", "products", "data"]
    for key in alt_keys:
        if key in raw and isinstance(raw[key], (list, dict)):
            val = raw[key]
            if isinstance(val, list):
                return {"items": val}
            return val

    # 케이스 3: 메타 키를 제외한 나머지가 실제 필드 데이터인 경우
    # 예: {"name": "재경사", "region": "대구", "missing_fields": []}
    meta_keys = {"type", "confidence", "missing_fields", "reasoning", "error", "status"}
    remaining = {k: v for k, v in raw.items() if k not in meta_keys}

    if remaining:
        # 남은 값 중에 리스트 하나만 있고 그 안에 딕셔너리들이면 → 복수 항목
        values = list(remaining.values())
        if len(values) == 1 and isinstance(values[0], list):
            return {"items": values[0]}
        return remaining

    return {}


def _detect_token_type(token: str) -> str:
    """마스킹된 원본 토큰의 종류를 정규식으로 판별"""
    clean = re.sub(r'[\-\s]', '', token)
    
    if re.match(r'^[\d\*]{16}$', clean):
        return "CARD"        # 카드번호 (16자리)
    elif re.match(r'^[\d\*]{13}$', clean):
        # 원본에서 7번째 자리가 하이픈(-)이면 주민번호, 아니면 13자리 바코드
        if len(token) > 6 and token[6] == '-':
            return "SSN"
        return "BARCODE"
    elif re.match(r'^010[\d\*]{8}$', clean) or re.match(r'^0[\d\*]{8,10}$', clean):
        return "PHONE"       # 전화번호
    elif re.match(r'^[\d\*]{10,14}$', clean):
        return "BARCODE"     # 기타 길이의 바코드
    else:
        return "OTHER"


@router.post("/analyze", response_model=AnalyzeResponse)
def analyze_screenshot(request: AnalyzeRequest):
    """OCR 텍스트를 받아 분류 + 구조화 (v1)"""
    try:
        result = call_llm(
            system_prompt=get_system_prompt(),
            user_text=request.ocr_text
        )
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
    
@router.post("/analyze/v2", response_model=AnalyzeResponse)
def analyze_v2(request: AnalyzeRequest):
    """2단계 분석: 분류 → 타입별 상세 추출"""
    
    # 📥 요청 내용 로깅 — 앱에서 뭘 보냈는지 확인
    logger.info(f"[v2] 📥 요청 수신 | type: {request.type} | ocr_text({len(request.ocr_text)}자): {request.ocr_text[:200]}{'...' if len(request.ocr_text) > 200 else ''}")

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

    # === 1단계: 분류 ===
    # 앱에서 로컬로 타입을 확정해서 보내주면 LLM 분류 생략 (API 비용 절감!)
    if request.type:
        detected_type = request.type.value
        classify_confidence = 1.0  # 로컬 분류는 신뢰도 1.0
        logger.info(f"[v2] 로컬 분류 사용: {detected_type}")
    else:
        classify_result = call_llm_with_limit(
            call_llm,
            system_prompt=CLASSIFY_PROMPT,
            user_text=request.ocr_text
        )
        detected_type = classify_result.get("type", "MEMO")
        classify_confidence = classify_result.get("confidence", 0)
        logger.info(f"[v2] LLM 분류: {detected_type} (신뢰도: {classify_confidence})")
    
    # === 2단계: 타입별 상세 추출 ===
    extract_result = call_llm_with_limit(
        call_llm,
        system_prompt=get_type_prompt(detected_type),
        user_text=request.ocr_text
    )
    
    # 🔍 디버깅: GPT가 실제로 뭘 반환했는지 로그로 확인
    logger.info(f"[v2] 분류: {detected_type} | GPT 추출 원본: {json.dumps(extract_result, ensure_ascii=False, default=str)}")
    
    # 🚨 GPT 응답 형식을 유연하게 파싱
    extracted_fields = _extract_fields(extract_result)
    
    # 결과 합치기
    final = {
        "type": detected_type,
        "confidence": classify_confidence,
        "fields": extracted_fields,
        "missing_fields": extract_result.get("missing_fields", [])
    }
    final = validate_result(final)
    
    row_id = save_result(
        type=final["type"],
        confidence=final.get("confidence", 0),
        fields=json.dumps(final.get("fields", {}), ensure_ascii=False),
        image_hash=request.image_hash
    )
    
    # 마스킹 토큰 정보 구조화
    masked_info_list = []
    if request.masked_tokens:
        for token in request.masked_tokens:
            t_type = _detect_token_type(token)
            masked_info_list.append({
                "original": token,
                "type": t_type
            })

    return AnalyzeResponse(
        id=row_id,
        type=final["type"],
        confidence=final.get("confidence", 0),
        fields=final.get("fields", {}),
        missing_fields=final.get("missing_fields", []),
        status=final.get("status", "DRAFT"),
        masked_info=masked_info_list
    )


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

    if len(request.items) == 0:
        raise HTTPException(
            status_code=400,
            detail="분석할 항목이 없습니다"
        )

    results = []
    errors = []

    for idx, item in enumerate(request.items):
        try:
            logger.info(f"[batch] 항목 {idx+1}/{len(request.items)} 처리 중...")
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