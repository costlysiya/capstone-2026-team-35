from typing import Union, List
from fastapi import APIRouter, HTTPException, BackgroundTasks
from app.schemas import (
    AnalyzeRequest, AnalyzeResponse, BatchAnalyzeRequest, BatchAnalyzeResponse,
    BatchAsyncResponse, BatchStatusResponse, ClassifyResponse, BatchClassifyResponse,
    LLMClassifyResponse, LLMScheduleResponse, LLMPlaceResponse, LLMWishlistResponse, LLMMemoResponse,
    LLMBulkClassifyResponse, LLMBulkScheduleResponse, LLMBulkPlaceResponse, LLMBulkWishlistResponse, LLMBulkMemoResponse
)
from app.prompts import get_system_prompt, CLASSIFY_PROMPT, get_type_prompt
from app.validator import validate_result
from app.database import save_result, get_result_by_hash, get_results_by_hash
from app.llm_client import call_llm
from app.concurrency import call_llm_with_limit
import json
import logging
import re

import uuid

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["분석"])

# In-memory task state store
_task_store: dict[str, dict] = {}


def _extract_fields(raw: dict) -> dict:
    """Safely extract fields from LLM response."""
    # Case 1: "fields" key exists
    if "fields" in raw:
        fields = raw["fields"]
        if isinstance(fields, list):
            return {"items": fields}
        if isinstance(fields, dict):
            return fields
        return {}

    # Case 2: Alternative keys
    alt_keys = ["places", "items", "results", "products", "data"]
    for key in alt_keys:
        if key in raw and isinstance(raw[key], (list, dict)):
            val = raw[key]
            if isinstance(val, list):
                return {"items": val}
            return val

    # Case 3: Extract non-meta keys
    meta_keys = {"type", "confidence", "missing_fields", "reasoning", "error", "status"}
    remaining = {k: v for k, v in raw.items() if k not in meta_keys}

    if remaining:
        # If remaining is a single list of dicts, treat as plural items
        values = list(remaining.values())
        if len(values) == 1 and isinstance(values[0], list):
            return {"items": values[0]}
        return remaining

    return {}


def _detect_token_type(token: str) -> str:
    """Determine original token type from masked token via regex."""
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
async def analyze_screenshot(request: AnalyzeRequest):
    """Analyze OCR text and extract structured data (v1). v2로 내부 리다이렉트합니다."""
    try:
        result = await analyze_v2(request)
        if isinstance(result, list):
            return result[0]
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"분석 실패: {str(e)}")
    
@router.post("/analyze/v2", response_model=Union[AnalyzeResponse, List[AnalyzeResponse]])
async def analyze_v2(request: AnalyzeRequest):
    """Two-stage analysis: Classify -> Detail Extraction."""
    
    # Log incoming request
    logger.info(f"[v2] 📥 요청 수신 | type: {request.type} | ocr_text({len(request.ocr_text)}자): {request.ocr_text[:200]}{'...' if len(request.ocr_text) > 200 else ''}")

    # Check cache
    if request.image_hash:
        cached_list = get_results_by_hash(request.image_hash)
        if cached_list:
            logger.info(f"[v2] 🗃️ 캐시 히트! hash={request.image_hash[:16]}... (총 {len(cached_list)}건)")
            responses = []
            for cached in cached_list:
                cached_fields = cached["fields"]
                if isinstance(cached_fields, str):
                    try:
                        cached_fields = json.loads(cached_fields)
                    except json.JSONDecodeError:
                        cached_fields = {}
                responses.append(AnalyzeResponse(
                    id=cached["id"],
                    type=cached["type"],
                    confidence=cached["confidence"],
                    fields=cached_fields,
                    missing_fields=[],
                    status=cached["status"]
                ))
            return responses if len(responses) > 1 else responses[0]

    # Validate input length
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
            user_text=request.ocr_text,
            response_format=LLMClassifyResponse
        )
        detected_type = classify_result.get("type", "MEMO")
        classify_confidence = classify_result.get("confidence", 0)
        logger.info(f"[v2] LLM 분류: {detected_type} (신뢰도: {classify_confidence}) (전체응답: {classify_result})")
    
    schema_map = {
        "SCHEDULE": LLMScheduleResponse,
        "PLACE": LLMPlaceResponse,
        "WISHLIST": LLMWishlistResponse,
        "MEMO": LLMMemoResponse
    }
    extract_schema = schema_map.get(detected_type, LLMMemoResponse)

    # === 2단계: 타입별 상세 추출 ===
    extract_result = call_llm_with_limit(
        call_llm,
        system_prompt=get_type_prompt(detected_type),
        user_text=request.ocr_text,
        response_format=extract_schema
    )
    
    # 🔍 디버깅: GPT가 실제로 뭘 반환했는지 로그로 확인
    logger.info(f"[v2] 분류: {detected_type} | GPT 추출 원본: {json.dumps(extract_result, ensure_ascii=False, default=str)}")
    
    # 🚨 GPT 응답 형식을 유연하게 파싱
    extracted_fields = _extract_fields(extract_result)
    
    # 마스킹 토큰 정보 구조화
    masked_info_list = []
    if request.masked_tokens:
        for token in request.masked_tokens:
            t_type = _detect_token_type(token)
            masked_info_list.append({
                "original": token,
                "type": t_type
            })

    # 다중 항목(items) 처리 로직 (단, MEMO(체크리스트 등)는 분할하지 않고 단일 카드로 유지)
    if detected_type != "MEMO" and "items" in extracted_fields and isinstance(extracted_fields["items"], list) and len(extracted_fields["items"]) > 0:
        logger.info(f"[v2] 다중 항목 감지: {len(extracted_fields['items'])}건 분할 저장 시작 (분류: {detected_type})")
        responses = []
        for item in extracted_fields["items"]:
            final = {
                "type": detected_type,
                "confidence": classify_confidence,
                "fields": item,
                "missing_fields": extract_result.get("missing_fields", [])
            }
            if "error" in extract_result:
                final["status"] = "ERROR"
            else:
                final = validate_result(final)
            
            row_id = save_result(
                type=final["type"],
                confidence=final.get("confidence", 0),
                fields=json.dumps(final.get("fields", {}), ensure_ascii=False),
                image_hash=request.image_hash,
                status=final.get("status", "DRAFT")
            )
            
            resp = AnalyzeResponse(
                id=row_id,
                type=final["type"],
                confidence=final.get("confidence", 0),
                fields=final.get("fields", {}),
                missing_fields=final.get("missing_fields", []),
                status=final.get("status", "DRAFT"),
                masked_info=masked_info_list
            )
            responses.append(resp)
        return responses if len(responses) > 1 else responses[0]
    
    # 단일 항목 처리 로직
    final = {
        "type": detected_type,
        "confidence": classify_confidence,
        "fields": extracted_fields,
        "missing_fields": extract_result.get("missing_fields", [])
    }
    
    if "error" in extract_result:
        final["status"] = "ERROR"
    else:
        final = validate_result(final)
    
    row_id = save_result(
        type=final["type"],
        confidence=final.get("confidence", 0),
        fields=json.dumps(final.get("fields", {}), ensure_ascii=False),
        image_hash=request.image_hash,
        status=final.get("status", "DRAFT")
    )

    return AnalyzeResponse(
        id=row_id,
        type=final["type"],
        confidence=final.get("confidence", 0),
        fields=final.get("fields", {}),
        missing_fields=final.get("missing_fields", []),
        status=final.get("status", "DRAFT"),
        masked_info=masked_info_list
    )

@router.post("/classify/batch", response_model=BatchClassifyResponse)
def classify_batch(request: BatchAnalyzeRequest):
    """
    초고속 분류 전용 묶음 API.
    대량의 텍스트에 대해 DB 저장 및 상세 추출 없이 대분류(SCHEDULE, PLACE 등)만 빠르게 수행합니다.
    최대 50개까지 허용.
    """
    if len(request.items) > 50:
        raise HTTPException(
            status_code=400,
            detail="초고속 분류 배치 요청은 최대 50개까지 가능합니다"
        )
    if len(request.items) == 0:
        raise HTTPException(status_code=400, detail="분석할 항목이 없습니다")

    results_map = {}
    valid_items = []
    
    for idx, item in enumerate(request.items):
        clean_text = item.ocr_text.strip()
        if len(clean_text) < 3:
            results_map[idx] = ClassifyResponse(
                index=idx, type="MEMO", confidence=0.0
            )
            continue
        if len(clean_text) > 5000:
            clean_text = clean_text[:5000]
        valid_items.append((idx, clean_text))

    if valid_items:
        bulk_texts = [f"[{idx}]\n{text}" for idx, text in valid_items]
        bulk_input_str = "\n---\n".join(bulk_texts)
        
        try:
            bulk_result = call_llm_with_limit(
                call_llm,
                system_prompt=get_system_prompt(is_bulk=True),
                user_text=bulk_input_str,
                response_format=LLMBulkClassifyResponse
            )
            
            for res_item in bulk_result.get("results", []):
                idx = res_item.get("index")
                if idx is not None:
                    results_map[idx] = ClassifyResponse(
                        index=idx,
                        type=res_item.get("type", "MEMO"),
                        confidence=res_item.get("confidence", 0.0)
                    )
        except Exception as e:
            logger.error(f"[classify_batch] 벌크 분석 에러: {e}")
            for idx, _ in valid_items:
                results_map[idx] = ClassifyResponse(
                    index=idx, type="MEMO", confidence=0.0
                )

    # 인덱스 순서대로 조립
    final_results = [results_map.get(i, ClassifyResponse(index=i, type="MEMO", confidence=0.0)) for i in range(len(request.items))]
    
    return BatchClassifyResponse(total=len(request.items), results=final_results)

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
    results_map = {}
    
    # 1. 1차 그룹화
    classify_needed = []
    type_groups = {"SCHEDULE": [], "PLACE": [], "WISHLIST": [], "MEMO": []}
    
    for idx, item in enumerate(request.items):
        clean_text = item.ocr_text.strip()
        if len(clean_text) < 3:
            errors.append({"index": idx, "error": "텍스트가 너무 짧습니다"})
            continue
        if len(clean_text) > 5000:
            item.ocr_text = clean_text[:5000]
            
        if item.type:
            type_groups[item.type.value].append((idx, item, 1.0)) # (idx, item, classify_confidence)
        else:
            classify_needed.append((idx, item))
            
    # 2. Bulk Classify
    if classify_needed:
        bulk_texts = [f"[{idx}]\n{item.ocr_text}" for idx, item in classify_needed]
        bulk_input_str = "\n---\n".join(bulk_texts)
        try:
            bulk_classify_result = call_llm_with_limit(
                call_llm,
                system_prompt=get_system_prompt(is_bulk=True),
                user_text=bulk_input_str,
                response_format=LLMBulkClassifyResponse
            )
            for res_item in bulk_classify_result.get("results", []):
                idx = res_item.get("index")
                ctype = res_item.get("type", "MEMO")
                cconf = res_item.get("confidence", 0.0)
                
                original_item = next((it for i, it in classify_needed if i == idx), None)
                if original_item:
                    type_groups.setdefault(ctype, []).append((idx, original_item, cconf))
        except Exception as e:
            logger.error(f"[bulk_analyze] Bulk classify error: {e}")
            for idx, item in classify_needed:
                type_groups["MEMO"].append((idx, item, 0.0))
                
    # 3. Bulk Extract per Type
    schema_map = {
        "SCHEDULE": LLMBulkScheduleResponse,
        "PLACE": LLMBulkPlaceResponse,
        "WISHLIST": LLMBulkWishlistResponse,
        "MEMO": LLMBulkMemoResponse
    }
    
    for ttype, titems in type_groups.items():
        if not titems:
            continue
            
        bulk_texts = [f"[{idx}]\n{item.ocr_text}" for idx, item, _ in titems]
        bulk_input_str = "\n---\n".join(bulk_texts)
        extract_schema = schema_map.get(ttype, LLMBulkMemoResponse)
        
        try:
            bulk_extract_result = call_llm_with_limit(
                call_llm,
                system_prompt=get_type_prompt(ttype, is_bulk=True),
                user_text=bulk_input_str,
                response_format=extract_schema
            )
            
            for res_item in bulk_extract_result.get("results", []):
                idx = res_item.get("index")
                if idx is None:
                    continue
                
                # find original item & confidence
                match = next(((item, cconf) for i, item, cconf in titems if i == idx), None)
                if not match:
                    continue
                original_item, classify_confidence = match
                
                # Token Masking Structure
                masked_info_list = []
                if original_item.masked_tokens:
                    for token in original_item.masked_tokens:
                        t_type = _detect_token_type(token)
                        masked_info_list.append({"original": token, "type": t_type})
                
                extracted_fields = _extract_fields(res_item)
                
                if ttype != "MEMO" and "items" in extracted_fields and isinstance(extracted_fields["items"], list) and len(extracted_fields["items"]) > 0:
                    responses = []
                    for single_item in extracted_fields["items"]:
                        final = {
                            "type": ttype,
                            "confidence": classify_confidence,
                            "fields": single_item,
                            "missing_fields": extracted_fields.get("missing_fields", [])
                        }
                        final = validate_result(final)
                        
                        row_id = save_result(
                            type=final["type"],
                            confidence=final.get("confidence", 0),
                            fields=json.dumps(final.get("fields", {}), ensure_ascii=False),
                            image_hash=original_item.image_hash,
                            status=final.get("status", "DRAFT")
                        )
                        responses.append(AnalyzeResponse(
                            id=row_id, original_index=idx, type=final["type"], confidence=final.get("confidence", 0),
                            fields=final.get("fields", {}), missing_fields=final.get("missing_fields", []),
                            status=final.get("status", "DRAFT"), masked_info=masked_info_list
                        ))
                    
                    if len(responses) == 1:
                        results_map[idx] = responses[0]
                    else:
                        # 다중 항목이면 list로 매핑
                        results_map[idx] = responses
                else:
                    final = {
                        "type": ttype,
                        "confidence": classify_confidence,
                        "fields": extracted_fields.get("items", extracted_fields), # if single dict
                        "missing_fields": extracted_fields.get("missing_fields", [])
                    }
                    if ttype != "MEMO" or not isinstance(final["fields"], list):
                        final = validate_result(final)
                        
                    row_id = save_result(
                        type=final["type"],
                        confidence=final.get("confidence", 0),
                        fields=json.dumps(final.get("fields", {}), ensure_ascii=False),
                        image_hash=original_item.image_hash,
                        status=final.get("status", "DRAFT")
                    )
                    results_map[idx] = AnalyzeResponse(
                        id=row_id, original_index=idx, type=final["type"], confidence=final.get("confidence", 0),
                        fields=final.get("fields", {}), missing_fields=final.get("missing_fields", []),
                        status=final.get("status", "DRAFT"), masked_info=masked_info_list
                    )
        except Exception as e:
            logger.error(f"[bulk_analyze] Bulk extract error for type {ttype}: {e}")
            for idx, _, _ in titems:
                errors.append({"index": idx, "error": str(e)})
                
    # 순서대로 리스트 조립 (Flatten arrays if multiple items detected)
    for i in range(len(request.items)):
        if i in results_map:
            val = results_map[i]
            if isinstance(val, list):
                results.extend(val)
            else:
                results.append(val)

    return BatchAnalyzeResponse(
        total=len(request.items),
        success=len(results),
        failed=len(errors),
        results=results,
        errors=errors
    )


def _process_batch_background(task_id: str, request: BatchAnalyzeRequest):
    """백그라운드에서 배치 항목을 Bulk 분석하고 상태를 업데이트하는 워커"""
    try:
        _task_store[task_id]["status"] = "PROCESSING"
        
        logger.info(f"[async_batch] {task_id} - Bulk 분석 시작 (총 {len(request.items)}건)")
        response = analyze_batch(request)
        
        _task_store[task_id]["results"] = response.results
        _task_store[task_id]["errors"] = response.errors
        _task_store[task_id]["completed"] = response.success
        _task_store[task_id]["failed"] = response.failed
        _task_store[task_id]["status"] = "COMPLETED"
        logger.info(f"[async_batch] {task_id} - Bulk 분석 완료")
    
    except Exception as e:
        logger.error(f"[async_batch] {task_id} - 전체 프로세스 실패: {e}")
        _task_store[task_id]["status"] = "ERROR"
        _task_store[task_id]["errors"].append({"index": -1, "error": f"백그라운드 작업 중단됨: {str(e)}"})


@router.post("/analyze/batch/async", response_model=BatchAsyncResponse, status_code=202)
def analyze_batch_async(request: BatchAnalyzeRequest, background_tasks: BackgroundTasks):
    """
    [비동기 큐] 복수 이미지를 접수하고 즉시 반환.
    백그라운드에서 순차적으로 분석을 진행합니다.
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

    task_id = str(uuid.uuid4())
    
    # 딕셔너리에 상태 초기화 등록
    _task_store[task_id] = {
        "status": "PENDING",
        "total": len(request.items),
        "completed": 0,
        "failed": 0,
        "results": [],
        "errors": []
    }

    # 백그라운드 태스크 등록
    background_tasks.add_task(_process_batch_background, task_id, request)

    logger.info(f"[async_batch] 비동기 작업 접수 완료: {task_id} (총 {len(request.items)}건)")
    
    return BatchAsyncResponse(task_id=task_id)


@router.get("/tasks/{task_id}/status", response_model=BatchStatusResponse)
def get_task_status(task_id: str):
    """
    진행 중인 비동기 배치 작업의 상태를 조회합니다.
    (Polling 방식으로 호출)
    """
    if task_id not in _task_store:
        raise HTTPException(status_code=404, detail="존재하지 않거나 만료된 작업입니다.")
    
    task_data = _task_store[task_id]
    
    return BatchStatusResponse(
        task_id=task_id,
        status=task_data["status"],
        total=task_data["total"],
        completed=task_data["completed"],
        failed=task_data["failed"],
        results=task_data["results"],
        errors=task_data["errors"]
    )