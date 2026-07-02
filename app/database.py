import sqlite3
from datetime import datetime

DB_PATH = "soseng.db"

def get_db():
    """DB 연결 가져오기"""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row  # 딕셔너리처럼 접근 가능
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
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    conn.close()

def save_result(type: str, confidence: float, fields: str):
    """분석 결과 저장"""
    conn = get_db()
    cursor = conn.execute(
        "INSERT INTO screenshots (type, confidence, fields) VALUES (?, ?, ?)",
        (type, confidence, fields)
    )
    conn.commit()
    row_id = cursor.lastrowid
    conn.close()
    return row_id

def get_all_results():
    """저장된 모든 결과 조회"""
    conn = get_db()
    rows = conn.execute("SELECT * FROM screenshots ORDER BY created_at DESC").fetchall()
    conn.close()
    return [dict(row) for row in rows]

def update_status(id: int, status: str):
    """상태 업데이트 (DRAFT → CONFIRMED)"""
    conn = get_db()
    conn.execute("UPDATE screenshots SET status = ? WHERE id = ?", (status, id))
    conn.commit()
    conn.close()