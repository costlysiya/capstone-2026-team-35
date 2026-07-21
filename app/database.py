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
    conn.commit()
    conn.close()

def save_result(type: str, confidence: float, fields: str, image_hash: str = None):
    """분석 결과 저장 (image_hash: 중복 분석 방지용 이미지 해시)"""
    conn = get_db()
    cursor = conn.execute(
        "INSERT INTO screenshots (type, confidence, fields, image_hash) VALUES (?, ?, ?, ?)",
        (type, confidence, fields, image_hash)
    )
    conn.commit()
    row_id = cursor.lastrowid
    conn.close()
    return row_id

def get_result_by_hash(image_hash: str):
    """이미지 해시로 기존 분석 결과 조회 (캐시 히트 확인)"""
    conn = get_db()
    row = conn.execute(
        "SELECT * FROM screenshots WHERE image_hash = ? ORDER BY created_at DESC LIMIT 1",
        (image_hash,)
    ).fetchone()
    conn.close()
    if row:
        return dict(row)
    return None

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