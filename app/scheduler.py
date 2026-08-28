import asyncio
import logging
import json
from datetime import datetime, timedelta
from app.database import get_db, save_notification

logger = logging.getLogger(__name__)

async def notification_scheduler_job():
    """Check DB periodically to create upcoming notifications."""
    logger.info("Notification scheduler started.")
    while True:
        try:
            logger.info("Checking for new notifications...")
            check_and_create_notifications()
            logger.info("Notification check complete.")
        except Exception as e:
            logger.error(f"Scheduler error: {e}")
            
        await asyncio.sleep(60)

def check_and_create_notifications():
    """Find schedules expiring today/tomorrow and save to notifications table."""
    conn = get_db()
    
    tokens_row = conn.execute("SELECT token FROM device_tokens").fetchall()
    if not tokens_row:
        conn.close()
        return
        
    now = datetime.now()
    today_str = now.strftime("%Y-%m-%d")
    tomorrow_str = (now + timedelta(days=1)).strftime("%Y-%m-%d")
    
    rows = conn.execute("SELECT id, type, fields FROM screenshots WHERE type IN ('SCHEDULE', 'GIFTICON') AND status IN ('DRAFT', 'CONFIRMED')").fetchall()
    
    for row in rows:
        result_id = row["id"]
        fields_str = row["fields"]
        try:
            fields = json.loads(fields_str)
        except json.JSONDecodeError:
            continue
            
        items = fields if isinstance(fields, list) else [fields]
            
        for item in items:
            if not isinstance(item, dict):
                continue
                
            title = item.get("title", "일정")
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
                noti_title = f"🔔 {formatted_date} 오늘 일정/만료 알림"
                body = f"[{title}] 항목이 오늘({formatted_date}) 예정/만료입니다."
            elif target_date == tomorrow_str:
                noti_title = f"🔔 {formatted_date} 내일 일정/만료 알림"
                body = f"[{title}] 항목이 내일({formatted_date}) 예정/만료입니다."
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
                    save_notification(device_token, noti_title, body, result_id)
                    logger.info(f"👉 알림 생성 완료: {title} (기기: {device_token[:8]}...)")
    
    conn.close()

def start_scheduler():
    """백그라운드에서 스케줄러 루프를 실행합니다."""
    asyncio.create_task(notification_scheduler_job())
