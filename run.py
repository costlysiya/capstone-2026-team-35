import uvicorn
import logging

# 로그 레벨 설정 — 디버깅용
logging.basicConfig(level=logging.INFO)

if __name__ == "__main__":
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)