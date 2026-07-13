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