#!/bin/bash
# setup_env.sh
# macOS/Linux bash script to set up Python virtual environment for on-device AI demo.

echo "========== 온디바이스 AI 개발 환경 구축 시작 (macOS/Linux) =========="

# 1. Python3 설치 확인
if ! command -v python3 &> /dev/null
then
    echo "에러: python3가 시스템에 설치되어 있지 않거나 PATH에 추가되지 않았습니다. Python을 설치해 주세요."
    exit 1
fi

python_version=$(python3 --version)
echo "사용 가능한 Python 버전: $python_version"

# 2. 가상환경 생성 (venv)
if [ ! -d "venv" ]; then
    echo "가상환경(venv) 생성 중..."
    python3 -m venv venv
    if [ $? -ne 0 ]; then
        echo "에러: 가상환경 생성에 실패했습니다."
        exit 1
    fi
    echo "가상환경 생성 완료."
else
    echo "이미 가상환경(venv) 폴더가 존재합니다. 생략합니다."
fi

# 3. pip 업그레이드 및 라이브러리 설치
echo "필수 라이브러리 설치 진행 중..."
./venv/bin/python -m pip install --upgrade pip
./venv/bin/pip install -r requirements.txt

if [ $? -eq 0 ]; then
    echo "========== 환경 구축 완료! =========="
    echo "학습을 시작하려면 다음 명령어를 실행하세요:"
    echo "  ./venv/bin/python src/train.py"
else
    echo "에러: 라이브러리 설치 도중 오류가 발생했습니다."
    exit 1
fi
