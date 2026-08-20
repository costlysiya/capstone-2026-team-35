import firebase_admin
from firebase_admin import credentials, messaging
import os
import logging
from app.database import get_db

logger = logging.getLogger(__name__)

# firebase-key.json 파일 경로 (SSS-app 루트 폴더)
KEY_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'firebase-key.json')

def init_firebase():
    """앱 시작 시 Firebase 초기화"""
    if not os.path.exists(KEY_PATH):
        logger.warning(f"⚠️ FCM 키 파일을 찾을 수 없습니다: {KEY_PATH}")
        logger.warning("푸시 알림 기능이 작동하지 않습니다. (키 파일을 넣고 서버를 재시작해주세요)")
        return False
        
    try:
        # 중복 초기화 방지
        if not firebase_admin._apps:
            cred = credentials.Certificate(KEY_PATH)
            firebase_admin.initialize_app(cred)
            logger.info("✅ Firebase Admin SDK 초기화 성공!")
        return True
    except Exception as e:
        logger.error(f"❌ Firebase 초기화 실패: {e}")
        return False

def remove_invalid_token(token: str):
    """앱이 삭제되거나 만료된 기기 토큰을 DB에서 안전하게 지웁니다."""
    try:
        conn = get_db()
        conn.execute("DELETE FROM device_tokens WHERE token = ?", (token,))
        conn.commit()
        conn.close()
        logger.info(f"🗑️ 만료된 기기 토큰 삭제 완료: {token[:10]}...")
    except Exception as e:
        logger.error(f"토큰 삭제 중 오류 발생: {e}")

def send_push_notification(device_token: str, title: str, body: str, data: dict = None):
    """특정 기기로 실제 푸시 팝업을 쏩니다."""
    # Firebase가 아직 초기화되지 않았다면 조용히 패스 (에러 내지 않음)
    if not firebase_admin._apps:
        return False
        
    try:
        # 데이터는 반드시 모두 문자열이어야 함
        stringified_data = {}
        if data:
            for k, v in data.items():
                stringified_data[k] = str(v)
                
        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            token=device_token,
            data=stringified_data
        )
        
        # 파이어베이스 서버로 전송!
        response = messaging.send(message)
        logger.info(f"📨 푸시 알림 발송 성공! (ID: {response})")
        return True
        
    except messaging.UnregisteredError:
        logger.warning(f"⚠️ 기기에서 앱이 삭제되었거나 토큰이 만료되었습니다.")
        remove_invalid_token(device_token)
        return False
    except Exception as e:
        logger.error(f"❌ 푸시 알림 발송 중 알 수 없는 에러: {e}")
        return False
