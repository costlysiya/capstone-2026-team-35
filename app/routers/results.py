from typing import Optional
from fastapi import APIRouter, HTTPException, Query, Response
from app.database import (
    get_all_results, get_result_by_id, get_results_by_type,
    get_results_by_status, update_status, update_fields, delete_result,
    search_results
)
from app.schemas import ResultConfirmRequest
import json
from app.validator import revalidate_after_edit
from app.calendar import generate_ics

router = APIRouter(prefix="/api/results", tags=["결과"])


@router.get("")
def list_results(
    type: Optional[str] = Query(None, description="타입 필터 (SCHEDULE, PLACE, WISHLIST, MEMO)"),
    status: Optional[str] = Query(None, description="상태 필터 (DRAFT, CONFIRMED, NEEDS_EDIT)"),
    q: Optional[str] = Query(None, description="통합 검색어 (fields 내 텍스트 검색)"),
    region: Optional[str] = Query(None, description="지역 필터 (PLACE 전용, 예: '서울')"),
    category: Optional[str] = Query(None, description="카테고리 필터 (PLACE 전용, 예: '카페')"),
    page: int = Query(1, description="페이지 번호 (1부터 시작)", ge=1),
    limit: int = Query(20, description="페이지 당 항목 수", ge=1, le=100)
):
    """
    저장된 분석 결과 목록 조회 (검색 및 페이지네이션 지원).
    """
    offset = (page - 1) * limit
    
    search_data = search_results(
        type=type, status=status, q=q, region=region, category=category, limit=limit, offset=offset
    )
    
    results = search_data["items"]

    # fields 문자열 파싱
    for r in results:
        if isinstance(r.get("fields"), str):
            try:
                r["fields"] = json.loads(r["fields"])
            except json.JSONDecodeError:
                r["fields"] = {}

    return {
        "total": search_data["total"],
        "page": page,
        "limit": limit,
        "items": results
    }


@router.get("/{id}")
def get_result(id: int):
    """단건 결과 조회"""
    result = get_result_by_id(id)
    if not result:
        raise HTTPException(status_code=404, detail=f"결과 #{id}을(를) 찾을 수 없습니다")

    # fields 파싱
    if isinstance(result.get("fields"), str):
        try:
            result["fields"] = json.loads(result["fields"])
        except json.JSONDecodeError:
            result["fields"] = {}

    # MEMO 카테고리가 CONFIRMED 상태일 경우 보안 및 통신량 절약을 위해 원본 데이터(body) 숨김 처리
    if result.get("status") == "CONFIRMED" and result.get("type") == "MEMO":
        if "body" in result["fields"]:
            result["fields"]["body"] = "[AI 분석 완료 - 원문 숨김 처리됨]"

    # SCHEDULE 타입 시 ical 렌더링 값 추가
    if result.get("type") == "SCHEDULE":
        result["ical_string"] = generate_ics(result["fields"])

    return result

@router.get("/{id}/ical")
def download_ical(id: int):
    """iCalendar (.ics) 파일 다운로드"""
    result = get_result_by_id(id)
    if not result:
        raise HTTPException(status_code=404, detail=f"결과 #{id}을(를) 찾을 수 없습니다")
        
    if result.get("type") != "SCHEDULE":
        raise HTTPException(status_code=400, detail="일정(SCHEDULE) 타입만 캘린더 연동이 가능합니다")
        
    if isinstance(result.get("fields"), str):
        try:
            fields = json.loads(result["fields"])
        except json.JSONDecodeError:
            fields = {}
    else:
        fields = result.get("fields", {})
        
    ics_content = generate_ics(fields)
    
    return Response(
        content=ics_content,
        media_type="text/calendar",
        headers={
            "Content-Disposition": f'attachment; filename="schedule_{id}.ics"'
        }
    )


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