from fastapi import APIRouter, HTTPException, Query
from app.schemas import TokenRequest, NotificationResponse
from app.database import save_device_token, get_notifications, mark_notification_read
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/notifications", tags=["알림"])


@router.post("/token", status_code=200)
def register_device_token(request: TokenRequest):
    """
    앱이 구동될 때 FCM 등에서 받은 기기 고유 토큰을 서버에 등록합니다.
    """
    if not request.device_token.strip():
        raise HTTPException(status_code=400, detail="유효하지 않은 기기 토큰입니다.")

    save_device_token(request.device_token)
    logger.info(f"📱 기기 토큰 등록됨: {request.device_token[:10]}...")
    return {"message": "기기 토큰이 성공적으로 등록되었습니다."}


@router.get("", response_model=list[NotificationResponse])
def list_notifications(
    device_token: str = Query(...), limit: int = 50, offset: int = 0
):
    """
    특정 기기의 알림 내역(Inbox)을 페이징하여 조회합니다.
    """
    if not device_token.strip():
        raise HTTPException(
            status_code=400, detail="device_token 파라미터가 필요합니다."
        )

    results = get_notifications(device_token, limit, offset)
    return results


@router.put("/{id}/read")
def read_notification(id: int):
    """
    사용자가 알림 탭에서 알림을 확인(클릭)했을 때 호출하여 읽음 처리합니다.
    """
    success = mark_notification_read(id)
    if not success:
        raise HTTPException(
            status_code=404, detail="알림을 찾을 수 없거나 이미 읽음 처리되었습니다."
        )

    return {"message": "알림 읽음 처리 완료"}
