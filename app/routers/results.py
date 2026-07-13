from typing import Optional
from fastapi import APIRouter, HTTPException, Query
from app.database import (
    get_all_results, get_result_by_id, get_results_by_type,
    get_results_by_status, update_status, update_fields, delete_result
)
from app.schemas import ResultConfirmRequest
import json
from app.validator import revalidate_after_edit

router = APIRouter(prefix="/api/results", tags=["결과"])


@router.get("")
def list_results(
    type: Optional[str] = Query(None, description="타입 필터 (SCHEDULE, PLACE, WISHLIST, MEMO)"),
    status: Optional[str] = Query(None, description="상태 필터 (DRAFT, CONFIRMED, NEEDS_EDIT)")
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