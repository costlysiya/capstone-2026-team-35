import os
import pickle
import pandas as pd
import numpy as np
from PIL import Image
from sklearn.model_selection import train_test_split
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.decomposition import TruncatedSVD

import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
import torchvision.transforms as transforms
import torchvision.models as models
from tqdm import tqdm

# 1. 설정 정보
DATASET_PATH = "/Users/chaeyoon/Library/CloudStorage/GoogleDrive-costlysiya@gmail.com/내 드라이브/졸과"
CSV_PATH = "./dataset.csv"
MODEL_SAVE_PATH = "./multimodal_model.pth"
TEXT_PROCESSOR_PATH = "./text_processors.pkl"
NUM_CLASSES = 4
SVD_DIM = 50  # 현재 데이터셋 크기(81개)를 고려하여 차원 수를 50으로 조절 (데이터가 늘어나면 100~200으로 확장)

# 2. 디바이스 설정 (Apple Silicon GPU 가속 적용)
device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
print(f"🖥️ 활성화된 학습 디바이스: {device}")

# 3. 텍스트 특징 추출기 학습 및 차원 축소 (TF-IDF + Truncated SVD)
def build_text_features(df):
    print("📝 텍스트 전처리 및 차원 축소(TF-IDF + SVD)를 실행합니다...")
    # 결측치 빈 문자열 처리
    df['extracted_text'] = df['extracted_text'].fillna('')
    
    # TF-IDF 벡터라이저 (한글 형태소 분석기 없이 띄어쓰기 기준으로 우선 생성)
    vectorizer = TfidfVectorizer(max_features=5000, min_df=2)
    tfidf_matrix = vectorizer.fit_transform(df['extracted_text'])
    
    # Truncated SVD 차원 축소
    svd = TruncatedSVD(n_components=SVD_DIM, random_state=42)
    svd_matrix = svd.fit_transform(tfidf_matrix)
    
    # 학습된 벡터라이저와 SVD 모델 저장 (추후 앱/서버 인퍼런스용)
    with open(TEXT_PROCESSOR_PATH, 'wb') as f:
        pickle.dump({'vectorizer': vectorizer, 'svd': svd}, f)
    print(f"💾 텍스트 프로세서 저장 완료 -> {TEXT_PROCESSOR_PATH}")
    
    return svd_matrix

# 4. PyTorch 커스텀 데이터셋 정의
class MultimodalDataset(Dataset):
    def __init__(self, df, svd_features, dataset_path, transform=None):
        self.df = df.reset_index(drop=True)
        self.svd_features = svd_features
        self.dataset_path = dataset_path
        self.transform = transform
        
    def __len__(self):
        return len(self.df)
        
    def __getitem__(self, idx):
        # 이미지 로드
        img_rel_path = self.df.loc[idx, 'file_path']
        img_abs_path = os.path.join(self.dataset_path, img_rel_path)
        
        try:
            image = Image.open(img_abs_path).convert('RGB')
        except Exception as e:
            # 이미지 손상/누락 시 더미 이미지 생성
            image = Image.new('RGB', (224, 224), (255, 255, 255))
            
        if self.transform:
            image = self.transform(image)
            
        # 텍스트 SVD 피처 벡터
        text_vector = torch.tensor(self.svd_features[idx], dtype=torch.float32)
        
        # 라벨 (0: SCHEDULE, 1: PLACE, 2: WISHLIST, 3: MEMO)
        label = torch.tensor(self.df.loc[idx, 'label'], dtype=torch.long)
        
        return image, text_vector, label

# 5. Multimodal Late Fusion AI 모델 정의 (MobileNetV2 + Text MLP)
class MultimodalFusionClassifier(nn.Module):
    def __init__(self, text_dim=50, num_classes=4):
        super(MultimodalFusionClassifier, self).__init__()
        # 이미지 브랜치 (Pre-trained MobileNetV2)
        mobilenet = models.mobilenet_v2(pretrained=True)
        
        # 가벼운 전이학습을 위해 MobileNet의 기본 백본 가중치는 동결(Freeze)
        for param in mobilenet.parameters():
            param.requires_grad = False
            
        self.image_features = mobilenet.features
        self.pool = nn.AdaptiveAvgPool2d((1, 1))
        
        # 이미지 차원 축소 (1280 -> 64)
        self.image_fc = nn.Sequential(
            nn.Linear(1280, 64),
            nn.BatchNorm1d(64),
            nn.ReLU(),
            nn.Dropout(0.3)
        )
        
        # 텍스트 브랜치 (SVD 벡터 50 -> 32)
        self.text_fc = nn.Sequential(
            nn.Linear(text_dim, 64),
            nn.BatchNorm1d(64),
            nn.ReLU(),
            nn.Linear(64, 32),
            nn.BatchNorm1d(32),
            nn.ReLU(),
            nn.Dropout(0.3)
        )
        
        # 융합 레이어 (이미지 64 + 텍스트 32 = 96 차원 -> Softmax 4개 카테고리)
        self.fusion_fc = nn.Sequential(
            nn.Linear(64 + 32, 64),
            nn.ReLU(),
            nn.Linear(64, num_classes)
        )
        
    def forward(self, image, text_vector):
        # 1. 이미지 피처 추출
        img_feats = self.image_features(image)
        img_feats = self.pool(img_feats)
        img_feats = torch.flatten(img_feats, 1)
        img_out = self.image_fc(img_feats)
        
        # 2. 텍스트 피처 추출
        text_out = self.text_fc(text_vector)
        
        # 3. 두 피처의 Late Fusion 결합 (Concatenate)
        combined = torch.cat((img_out, text_out), dim=1)
        
        # 4. 최종 카테고리 분류
        logits = self.fusion_fc(combined)
        return logits

def main():
    # 데이터셋 CSV 파일 존재 여부 확인
    if not os.path.exists(CSV_PATH):
        print(f"❌ 오류: {CSV_PATH} 파일이 없습니다. build_dataset.py를 먼저 실행해 주세요.")
        return
        
    # 1. 데이터 로드
    df = pd.read_csv(CSV_PATH)
    print(f"📊 로드된 총 데이터 개수: {len(df)}")
    
    # 2. 텍스트 특징 벡터 구축
    svd_features = build_text_features(df)
    
    # 3. 데이터셋 분할 (학습 데이터: 검증 데이터 = 8:2)
    # 데이터셋 크기가 매우 작은 초기 상태이므로 stratify 옵션 적용
    train_df, val_df, train_svd, val_svd = train_test_split(
        df, svd_features, test_size=0.2, random_state=42, stratify=df['label']
    )
    print(f"📈 학습 데이터: {len(train_df)}개, 검증 데이터: {len(val_df)}개")
    
    # 4. 이미지 변환(Transform) 정의
    # MobileNet 규격인 224x224 크기로 이미지 리사이즈 및 정규화
    train_transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.RandomHorizontalFlip(),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])
    
    val_transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])
    
    # DataLoader 구축
    train_dataset = MultimodalDataset(train_df, train_svd, DATASET_PATH, transform=train_transform)
    val_dataset = MultimodalDataset(val_df, val_svd, DATASET_PATH, transform=val_transform)
    
    # 데이터셋 크기를 고려하여 배치 사이즈 8로 설정
    train_loader = DataLoader(train_dataset, batch_size=8, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=8, shuffle=False)
    
    # 5. 모델 정의, 손실함수, 옵티마이저 생성
    model = MultimodalFusionClassifier(text_dim=SVD_DIM, num_classes=NUM_CLASSES).to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.001)
    
    # 6. 학습 루프 (Epoch: 15)
    epochs = 15
    print("\n🚀 학습을 시작합니다...")
    
    for epoch in range(epochs):
        model.train()
        running_loss = 0.0
        correct_train = 0
        total_train = 0
        
        for images, texts, labels in train_loader:
            images = images.to(device)
            texts = texts.to(device)
            labels = labels.to(device)
            
            optimizer.zero_grad()
            outputs = model(images, texts)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()
            
            running_loss += loss.item() * images.size(0)
            _, predicted = torch.max(outputs.data, 1)
            total_train += labels.size(0)
            correct_train += (predicted == labels).sum().item()
            
        epoch_loss = running_loss / len(train_dataset)
        train_acc = correct_train / total_train
        
        # 검증 루프
        model.eval()
        val_loss = 0.0
        correct_val = 0
        total_val = 0
        
        with torch.no_grad():
            for images, texts, labels in val_loader:
                images = images.to(device)
                texts = texts.to(device)
                labels = labels.to(device)
                
                outputs = model(images, texts)
                loss = criterion(outputs, labels)
                
                val_loss += loss.item() * images.size(0)
                _, predicted = torch.max(outputs.data, 1)
                total_val += labels.size(0)
                correct_val += (predicted == labels).sum().item()
                
        val_loss = val_loss / len(val_dataset)
        val_acc = correct_val / total_val
        
        print(f"Epoch {epoch+1:02d}/{epochs:02d} | Train Loss: {epoch_loss:.4f} Acc: {train_acc:.4f} | Val Loss: {val_loss:.4f} Acc: {val_acc:.4f}")
        
    # 7. 학습 완료 모델 저장
    torch.save(model.state_dict(), MODEL_SAVE_PATH)
    print(f"\n🎉 모델 학습 완료 및 저장 완료 -> {MODEL_SAVE_PATH}")

if __name__ == "__main__":
    main()
