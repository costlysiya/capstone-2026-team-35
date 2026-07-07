# setup_env.ps1
# Windows PowerShell Script to set up Python virtual environment for on-device AI demo.

Write-Host "========== 온디바이스 AI 개발 환경 구축 시작 ==========" -ForegroundColor Cyan

# 1. Python 설치 확인
$pythonExists = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonExists) {
    Write-Error "Python이 시스템에 설치되어 있지 않거나 PATH에 추가되지 않았습니다. Python을 설치해 주세요."
    exit 1
}

$pythonVersion = python --version
Write-Host "사용 가능한 Python 버전: $pythonVersion" -ForegroundColor Green

# 2. 가상환경 생성 (venv)
if (-not (Test-Path "venv")) {
    Write-Host "가상환경(venv) 생성 중..." -ForegroundColor Yellow
    python -m venv venv
    if ($LASTEXITCODE -ne 0) {
        Write-Error "가상환경 생성에 실패했습니다."
        exit 1
    }
    Write-Host "가상환경 생성 완료." -ForegroundColor Green
} else {
    Write-Host "이미 가상환경(venv) 폴더가 존재합니다. 생략합니다." -ForegroundColor Gray
}

# 3. pip 업그레이드 및 라이브러리 설치
Write-Host "필수 라이브러리 설치 진행 중..." -ForegroundColor Yellow
& ".\venv\Scripts\python.exe" -m pip install --upgrade pip
& ".\venv\Scripts\pip.exe" install -r requirements.txt

if ($LASTEXITCODE -eq 0) {
    Write-Host "========== 환경 구축 완료! ==========" -ForegroundColor Green
    Write-Host "학습을 시작하려면 다음 명령어를 실행하세요:" -ForegroundColor Green
    Write-Host "  .\venv\Scripts\python.exe src/train.py" -ForegroundColor Cyan
} else {
    Write-Error "라이브러리 설치 도중 에러가 발생했습니다."
    exit 1
}
