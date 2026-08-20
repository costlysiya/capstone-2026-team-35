from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import init_db
from app.routers import analyze, results, notifications
from app.scheduler import start_scheduler
from app.fcm import init_firebase

app = FastAPI(
    title="소생 앱 API",
    description="스크린샷 정보 추출 및 관리 서버",
    version="0.2.0"
)

# ✅ CORS 설정 — Flutter 앱에서의 요청을 허용
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],          # 개발 중에는 전체 허용 (배포 시 제한)
    allow_credentials=True,
    allow_methods=["*"],          # GET, POST, PUT, DELETE 모두 허용
    allow_headers=["*"],
)

@app.on_event("startup")
def startup():
    init_db()
    init_firebase()
    start_scheduler()

# 라우터 연결
app.include_router(analyze.router)
app.include_router(results.router)
app.include_router(notifications.router)

@app.get("/")
def health():
    return {"status": "running", "version": "0.2.0"}