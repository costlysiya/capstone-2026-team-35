from fastapi import APIRouter
from app.database import get_all_results, update_status

# API 라우터 설정 (주소 앞에 /api/results가 기본으로 붙게 됩니다)
router = APIRouter(prefix="/api/results", tags=["결과"])

@router.get("")
def list_results():
    """저장된 모든 분석 결과 목록 조회"""
    return get_all_results()

@router.post("/{id}/confirm")
def confirm_result(id: int):
    """특정 분석 결과를 사용자가 승인(CONFIRMED) 상태로 변경"""
    update_status(id, "CONFIRMED")
    return {"message": f"결과 #{id}이(가) 승인되었습니다"}