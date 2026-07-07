import os
import shutil
from fastapi import FastAPI, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
from inference import SoSeangPredictor

app = FastAPI(title="소생 앱 AI 분류 로컬 서버")

# CORS 설정 (앱/웹 통신 허용)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 예측 엔진 초기화
predictor = None

@app.on_event("startup")
def startup_event():
    global predictor
    try:
        predictor = SoSeangPredictor()
    except Exception as e:
        print(f"❌ 예측 엔진 로드 실패: {e}")

@app.post("/classify")
async def classify_image(
    image: UploadFile = File(...),
    ocr_text: str = Form(...)
):
    """
    모바일 앱에서 업로드한 이미지 파일과 OCR 텍스트를 전달받아
    학습된 멀티모달 모델로 카테고리를 자동 분류합니다.
    """
    global predictor
    if predictor is None:
        return {"error": "모델이 준비되지 않았습니다."}
        
    # 임시 폴더 생성
    temp_dir = "./temp_uploads"
    os.makedirs(temp_dir, exist_ok=True)
    
    # 이미지 임시 저장
    temp_image_path = os.path.join(temp_dir, image.filename)
    with open(temp_image_path, "wb") as buffer:
        shutil.copyfileobj(image.file, buffer)
        
    try:
        # 모델 추론 실행
        result = predictor.predict(temp_image_path, ocr_text)
        
        # 카테고리 문자열을 Flutter 앱의 라벨 인덱스로 변환
        # (0: SCHEDULE, 1: PLACE, 2: WISHLIST, 3: MEMO)
        label_to_index = {
            "SCHEDULE": 0,
            "PLACE": 1,
            "WISHLIST": 2,
            "MEMO": 3
        }
        
        category_str = result["category"]
        category_index = label_to_index.get(category_str, 3) # 기본값 MEMO
        
        print(f"📥 [수신] OCR Text: '{ocr_text[:30]}...'")
        print(f"🏷️ [결과] 예측 카테고리: {category_str} (인덱스: {category_index}), 신뢰도: {result['confidence']:.4f}")
        
        # 임시 이미지 파일 삭제
        os.remove(temp_image_path)
        
        return {
            "category": category_str,
            "category_index": category_index,
            "confidence": result["confidence"],
            "all_probabilities": result["all_probabilities"]
        }
        
    except Exception as e:
        # 에러 발생 시 임시 파일 정리 및 에러 응답
        if os.path.exists(temp_image_path):
            os.remove(temp_image_path)
        print(f"❌ 추론 실패: {e}")
        return {"error": str(e)}

if __name__ == "__main__":
    # 로컬 IP를 자동 감지하거나 0.0.0.0으로 열어 동일 Wi-Fi 대역의 태블릿에서 접근 가능하게 설정
    uvicorn.run(app, host="0.0.0.0", port=8000)
