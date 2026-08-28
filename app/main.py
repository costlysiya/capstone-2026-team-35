from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import init_db
from app.routers import analyze, results, notifications
from app.scheduler import start_scheduler

app = FastAPI(
    title="소생 앱 API",
    description="스크린샷 정보 추출 및 관리 서버",
    version="0.2.0"
)

# CORS Configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
def startup():
    init_db()
    start_scheduler()

# Include routers
app.include_router(analyze.router)
app.include_router(results.router)
app.include_router(notifications.router)

@app.get("/")
def health():
    return {"status": "running", "version": "0.2.0"}