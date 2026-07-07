import os
import torch
import pickle
from PIL import Image
import torchvision.transforms as transforms
from train import MultimodalFusionClassifier  # 기존 train.py에서 모델 정의 재사용

# 1. 설정 및 경로
MODEL_PATH = "./multimodal_model.pth"
TEXT_PROCESSOR_PATH = "./text_processors.pkl"
LABEL_NAMES = ["SCHEDULE", "PLACE", "WISHLIST", "MEMO"]

class SoSeangPredictor:
    def __init__(self):
        # 디바이스 설정 (MPS 가속 또는 CPU)
        self.device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
        print(f"🔮 예측 엔진 초기화 중... (디바이스: {self.device})")
        
        # 1. 텍스트 프로세서(TF-IDF, SVD) 로드
        if not os.path.exists(TEXT_PROCESSOR_PATH):
            raise FileNotFoundError(f"❌ {TEXT_PROCESSOR_PATH} 파일이 없습니다. train.py를 먼저 실행해 주세요.")
        with open(TEXT_PROCESSOR_PATH, 'rb') as f:
            processors = pickle.load(f)
            self.vectorizer = processors['vectorizer']
            self.svd = processors['svd']
            
        # SVD 차원 정보 획득
        self.text_dim = self.svd.n_components
        
        # 2. PyTorch 모델 인스턴스 생성 및 가중치 로드
        if not os.path.exists(MODEL_PATH):
            raise FileNotFoundError(f"❌ {MODEL_PATH} 파일이 없습니다. train.py를 먼저 실행해 주세요.")
        self.model = MultimodalFusionClassifier(text_dim=self.text_dim, num_classes=len(LABEL_NAMES))
        self.model.load_state_dict(torch.load(MODEL_PATH, map_location=self.device))
        self.model.to(self.device)
        self.model.eval()  # 평가 모드 설정 (Dropout, BatchNorm 비활성화)
        
        # 3. 이미지 전처리 Transform 정의
        self.transform = transforms.Compose([
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
        ])
        print("✅ 예측 엔진 준비 완료!")

    def predict(self, image_path: str, ocr_text: str):
        """
        이미지 파일과 OCR 텍스트를 입력받아 예측된 카테고리를 반환합니다.
        """
        # 1. 이미지 로드 및 전처리
        if not os.path.exists(image_path):
            raise FileNotFoundError(f"❌ 이미지 파일을 찾을 수 없습니다: {image_path}")
        image = Image.open(image_path).convert('RGB')
        image_tensor = self.transform(image).unsqueeze(0).to(self.device) # 배치 차원 추가

        # 2. 텍스트 전처리 (TF-IDF + SVD)
        tfidf_vec = self.vectorizer.transform([ocr_text])
        svd_vec = self.svd.transform(tfidf_vec)
        text_tensor = torch.tensor(svd_vec, dtype=torch.float32).to(self.device)

        # 3. 모델 추론
        with torch.no_grad():
            outputs = self.model(image_tensor, text_tensor)
            probabilities = torch.softmax(outputs, dim=1)
            confidence, predicted_idx = torch.max(probabilities, 1)
            
        category = LABEL_NAMES[predicted_idx.item()]
        conf_score = confidence.item()
        
        return {
            "category": category,
            "confidence": conf_score,
            "all_probabilities": {LABEL_NAMES[i]: probabilities[0][i].item() for i in range(len(LABEL_NAMES))}
        }

# 테스트용 실행 예제
if __name__ == "__main__":
    # 임의의 테스트 텍스트와 이미지 경로 설정
    test_image = "/Users/chaeyoon/Library/CloudStorage/GoogleDrive-costlysiya@gmail.com/내 드라이브/졸과/SCHEDULE/sched_001.png"
    test_text = "스타벅스 아이스 아메리카노 기프티콘 유효기간 2026년 12월 31일까지 사용 가능"
    
    if os.path.exists(test_image):
        predictor = SoSeangPredictor()
        result = predictor.predict(test_image, test_text)
        print("\n🔍 --- 예측 결과 ---")
        print(f"🏷️ 예측 카테고리: {result['category']}")
        print(f"📈 신뢰도 (Confidence): {result['confidence']:.4f}")
        print(f"📊 상세 확률 분포: {result['all_probabilities']}")
    else:
        print("💡 테스트용 이미지가 지정된 경로에 없어 실제 추론 테스트를 생략합니다.")
        print("인퍼런스 코드는 정상 작성되었으므로 다른 파일에서 SoSeangPredictor를 import하여 사용해 주세요.")
