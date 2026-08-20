import asyncio
import logging
import json
from datetime import datetime, timedelta
from app.database import get_db, save_notification
from app.fcm import send_push_notification

logger = logging.getLogger(__name__)

async def notification_scheduler_job():
    """1시간마다 DB를 검사하여 다가오는 일정/기프티콘 알림을 생성합니다."""
    logger.info("🚀 백그라운드 스케줄러가 시작되었습니다. (1시간 주기)")
    while True:
        try:
            logger.info("⏰ 스케줄러: 알림 생성 체크 시작...")
            check_and_create_notifications()
            logger.info("⏰ 스케줄러: 알림 생성 체크 완료.")
        except Exception as e:
            logger.error(f"알림 스케줄러 에러: {e}")
            
        # 테스트용: 1분(60초) 대기 (기존: 3600초)
        await asyncio.sleep(60)

def check_and_create_notifications():
    """DB에서 오늘/내일 만료되는 일정을 찾아 알림 테이블에 저장"""
    conn = get_db()
    
    # 1. 등록된 모든 기기 토큰 가져오기 (현재 구조상 모든 기기에 알림을 저장)
    tokens_row = conn.execute("SELECT token FROM device_tokens").fetchall()
    if not tokens_row:
        conn.close()
        return
        
    now = datetime.now()
    today_str = now.strftime("%Y-%m-%d")
    tomorrow_str = (now + timedelta(days=1)).strftime("%Y-%m-%d")
    
    # 2. 분석 완료(CONFIRMED)된 일정 가져오기
    rows = conn.execute("SELECT id, fields FROM screenshots WHERE type = 'SCHEDULE' AND status = 'CONFIRMED'").fetchall()
    
    for row in rows:
        result_id = row["id"]
        fields_str = row["fields"]
        try:
            fields = json.loads(fields_str)
        except json.JSONDecodeError:
            continue
            
        # 단일 추출이든 다중 추출이든 리스트 형태로 묶어서 순회
        items = fields if isinstance(fields, list) else [fields]
            
        for item in items:
            if not isinstance(item, dict):
                continue
                
            title = item.get("title", "일정")
            # 만료일(expires_at) 또는 시작일(start_at) 기준
            target_date = item.get("expires_at") or item.get("start_at")
            
            if not target_date:
                continue
                
            # 대상 날짜가 오늘이나 내일인 경우에만 알림 내용 구성
            body = ""
            noti_title = ""
            
            # 날짜를 읽기 쉽게 변환 (예: 2026-08-20 -> 8월 20일)
            try:
                date_obj = datetime.strptime(target_date, "%Y-%m-%d")
                formatted_date = f"{date_obj.month}월 {date_obj.day}일"
            except ValueError:
                formatted_date = target_date
                
            if target_date == today_str:
                noti_title = f"🔔 {formatted_date} 오늘 일정 알림"
                body = f"[{title}] 일정이 오늘({formatted_date}) 예정되어 있습니다."
            elif target_date == tomorrow_str:
                noti_title = f"🔔 {formatted_date} 내일 일정 알림"
                body = f"[{title}] 일정이 내일({formatted_date}) 예정되어 있습니다."
            else:
                continue # 오늘이나 내일이 아니면 건너뜀
                
            # 각 토큰별로 중복 알림 방지 처리 후 생성
            for token_row in tokens_row:
                device_token = token_row["token"]
                
                # 동일한 result_id, 알림 제목, 오늘 날짜(date) 기준으로 중복 체크
                existing = conn.execute("""
                    SELECT 1 FROM notifications 
                    WHERE device_token = ? AND result_id = ? AND title = ? AND date(created_at) = date('now', 'localtime')
                """, (device_token, result_id, noti_title)).fetchone()
                
                if not existing:
                    noti_id = save_notification(device_token, noti_title, body, result_id)
                    logger.info(f"👉 DB 알림 생성 완료: {title} (기기: {device_token[:8]}...)")
                    
                    # 🚀 기기에 실제 푸시 알림 발송 시도
                    send_push_notification(
                        device_token=device_token, 
                        title=noti_title, 
                        body=body,
                        data={"result_id": str(result_id), "notification_id": str(noti_id)}
                    )
    
    conn.close()

def start_scheduler():
    """백그라운드에서 스케줄러 루프를 실행합니다."""
    asyncio.create_task(notification_scheduler_job())
