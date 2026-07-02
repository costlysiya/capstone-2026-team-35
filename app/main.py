from fastapi import FastAPI
from app.database import init_db
from app.routers import analyze, results

app = FastAPI(
    title="소생 앱 API",
    description="스크린샷 정보 추출 및 관리 서버",
    version="0.1.0"
)

@app.on_event("startup")
def startup():
    init_db()

# 라우터 연결
app.include_router(analyze.router)
app.include_router(results.router)

@app.get("/")
def health():
    return {"status": "running", "version": "0.1.0"}