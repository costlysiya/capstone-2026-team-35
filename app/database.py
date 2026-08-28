import sqlite3
import json
from datetime import datetime

DB_PATH = "soseng.db"

def get_db():
    """DB 연결 가져오기"""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    """테이블 생성 (앱 시작할 때 한 번)"""
    conn = get_db()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS screenshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            confidence REAL,
            fields TEXT,
            status TEXT DEFAULT 'DRAFT',
            image_hash TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    """)
    # 해시 인덱스 (캐시 조회 속도 향상)
    conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_image_hash ON screenshots(image_hash)
    """)
    
    # 기기 토큰 저장소
    conn.execute("""
        CREATE TABLE IF NOT EXISTS device_tokens (
            token TEXT PRIMARY KEY,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # 알림함(Inbox) 내역
    conn.execute("""
        CREATE TABLE IF NOT EXISTS notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_token TEXT,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            result_id INTEGER,
            is_read BOOLEAN DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    conn.commit()
    conn.close()

def save_result(type: str, confidence: float, fields: str, image_hash: str = None, status: str = 'DRAFT'):
    """분석 결과 저장 (image_hash: 중복 분석 방지용 이미지 해시)"""
    conn = get_db()
    cursor = conn.execute(
        "INSERT INTO screenshots (type, confidence, fields, image_hash, status) VALUES (?, ?, ?, ?, ?)",
        (type, confidence, fields, image_hash, status)
    )
    row_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return row_id

# Push Notifications

def save_device_token(token: str):
    """기기 토큰 저장 (Upsert)"""
    conn = get_db()
    # SQLite UPSERT
    conn.execute("""
        INSERT INTO device_tokens (token) 
        VALUES (?) 
        ON CONFLICT(token) DO UPDATE SET created_at = CURRENT_TIMESTAMP
    """, (token,))
    conn.commit()
    conn.close()

def save_notification(device_token: str, title: str, body: str, result_id: int = None) -> int:
    """새로운 알림 내역 저장"""
    conn = get_db()
    cursor = conn.execute("""
        INSERT INTO notifications (device_token, title, body, result_id)
        VALUES (?, ?, ?, ?)
    """, (device_token, title, body, result_id))
    row_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return row_id

def get_notifications(device_token: str, limit: int = 50, offset: int = 0) -> list[dict]:
    """특정 기기의 알림 내역 조회"""
    conn = get_db()
    cursor = conn.execute("""
        SELECT id, title, body, result_id, is_read, created_at
        FROM notifications
        WHERE device_token = ?
        ORDER BY created_at DESC, id DESC
        LIMIT ? OFFSET ?
    """, (device_token, limit, offset))
    rows = cursor.fetchall()
    conn.close()
    
    results = []
    for r in rows:
        results.append({
            "id": r["id"],
            "title": r["title"],
            "body": r["body"],
            "result_id": r["result_id"],
            "is_read": bool(r["is_read"]),
            "created_at": r["created_at"]
        })
    return results

def mark_notification_read(notification_id: int) -> bool:
    """알림 읽음 처리"""
    conn = get_db()
    cursor = conn.execute("UPDATE notifications SET is_read = 1 WHERE id = ?", (notification_id,))
    changes = cursor.rowcount
    conn.commit()
    conn.close()
    return changes > 0

def get_result_by_hash(image_hash: str):
    """이미지 해시로 기존 분석 결과 조회 (캐시 히트 확인) - 하위 호환성 유지"""
    conn = get_db()
    row = conn.execute(
        "SELECT * FROM screenshots WHERE image_hash = ? ORDER BY created_at DESC LIMIT 1",
        (image_hash,)
    ).fetchone()
    conn.close()
    if row:
        return dict(row)
    return None

def get_results_by_hash(image_hash: str) -> list[dict]:
    """이미지 해시로 등록된 모든 분석 결과를 조회 (다중 추출 분할 캐시 지원)"""
    conn = get_db()
    rows = conn.execute(
        "SELECT * FROM screenshots WHERE image_hash = ? ORDER BY id ASC",
        (image_hash,)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]

def get_result_by_id(id: int):
    """단건 조회"""
    conn = get_db()
    row = conn.execute("SELECT * FROM screenshots WHERE id = ?", (id,)).fetchone()
    conn.close()
    if row:
        return dict(row)
    return None

def get_all_results():
    """저장된 모든 결과 조회"""
    conn = get_db()
    rows = conn.execute("SELECT * FROM screenshots ORDER BY created_at DESC").fetchall()
    conn.close()
    return [dict(row) for row in rows]

def get_results_by_type(type: str):
    """타입별 결과 조회"""
    conn = get_db()
    rows = conn.execute(
        "SELECT * FROM screenshots WHERE type = ? ORDER BY created_at DESC",
        (type,)
    ).fetchall()
    conn.close()
    return [dict(row) for row in rows]

def get_results_by_status(status: str):
    """상태별 결과 조회"""
    conn = get_db()
    rows = conn.execute(
        "SELECT * FROM screenshots WHERE status = ? ORDER BY created_at DESC",
        (status,)
    ).fetchall()
    conn.close()
    return [dict(row) for row in rows]

def search_results(type: str = None, status: str = None, q: str = None, region: str = None, category: str = None, limit: int = 20, offset: int = 0):
    """
    통합 검색 및 필터, 페이지네이션 쿼리
    JSON 컬럼(fields)에서 직접 값 추출 및 LIKE 검색 적용
    """
    conn = get_db()
    
    query = "SELECT * FROM screenshots WHERE 1=1"
    params = []
    
    if type:
        query += " AND type = ?"
        params.append(type)
    if status:
        query += " AND status = ?"
        params.append(status)
    if region:
        # Search for region inside fields JSON
        query += " AND json_extract(fields, '$.region') LIKE ?"
        params.append(f"%{region}%")
    if category:
        query += " AND json_extract(fields, '$.category') = ?"
        params.append(category)
    if q:
        # Global text search across fields JSON
        query += " AND fields LIKE ?"
        params.append(f"%{q}%")
        
    query += " ORDER BY created_at DESC LIMIT ? OFFSET ?"
    params.extend([limit, offset])
    
    rows = conn.execute(query, tuple(params)).fetchall()
    
    # Count total for pagination
    count_query = "SELECT COUNT(*) FROM screenshots WHERE 1=1"
    count_params = params[:-2] # limit, offset 제외
    if type:
        count_query += " AND type = ?"
    if status:
        count_query += " AND status = ?"
    if region:
        count_query += " AND json_extract(fields, '$.region') LIKE ?"
    if category:
        count_query += " AND json_extract(fields, '$.category') = ?"
    if q:
        count_query += " AND fields LIKE ?"
        
    total_count = conn.execute(count_query, tuple(count_params)).fetchone()[0]
    
    conn.close()
    return {"total": total_count, "items": [dict(row) for row in rows]}

def update_fields(id: int, fields: str):
    """사용자가 수정한 필드 업데이트"""
    conn = get_db()
    now = datetime.now().isoformat()
    conn.execute(
        "UPDATE screenshots SET fields = ?, updated_at = ? WHERE id = ?",
        (fields, now, id)
    )
    conn.commit()
    conn.close()

def update_status(id: int, status: str):
    """상태 업데이트 (DRAFT → CONFIRMED)"""
    conn = get_db()
    now = datetime.now().isoformat()
    conn.execute(
        "UPDATE screenshots SET status = ?, updated_at = ? WHERE id = ?",
        (status, now, id)
    )
    conn.commit()
    conn.close()

def delete_result(id: int):
    """결과 삭제"""
    conn = get_db()
    conn.execute("DELETE FROM screenshots WHERE id = ?", (id,))
    conn.commit()
    conn.close()