# preprocess.py
import re
import json
import pandas as pd
import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.decomposition import TruncatedSVD
import joblib
import os

def clean_text(text):
    if not isinstance(text, str):
        return ""
    # 영문, 한글, 숫자만 남기고 특수문자는 공백으로 치환
    text = re.sub(r'[^가-힣a-zA-Z0-9\s]', ' ', text)
    # 연속된 공백을 하나로 결합
    text = re.sub(r'\s+', ' ', text)
    return text.strip().lower()

def build_preprocessing_pipeline(data_path, vocab_size=1000, svd_components=100):
    print(f"데이터 로드 중: {data_path}")
    df = pd.read_csv(data_path)
    
    # 텍스트 클리닝
    cleaned_texts = df['text'].apply(clean_text).tolist()
    
    # 1. TF-IDF 학습
    # token_pattern=r'(?u)\b\w+\b'를 사용하여 어절 단위(공백 구분)로 매칭
    vectorizer = TfidfVectorizer(max_features=vocab_size, token_pattern=r'(?u)\b\w+\b')
    tfidf_matrix = vectorizer.fit_transform(cleaned_texts)
    
    # 단어 사전 및 IDF 값 추출
    vocabulary = vectorizer.vocabulary_
    # JSON 직렬화를 위해 정수형 변환
    vocab_dict = {word: int(idx) for word, idx in vocabulary.items()}
    idf_list = vectorizer.idf_.tolist()
    
    # 실제 반영된 단어 개수
    actual_vocab_size = len(vocab_dict)
    print(f"구축된 단어 사전 크기: {actual_vocab_size}")
    
    # 2. Truncated SVD (LSA) 학습
    n_components = min(svd_components, actual_vocab_size - 1)
    print(f"Truncated SVD 차원 축소 진행: {actual_vocab_size}차원 -> {n_components}차원")
    svd = TruncatedSVD(n_components=n_components, random_state=42)
    svd_matrix = svd.fit_transform(tfidf_matrix)
    
    # SVD components_ 행렬 (shape: n_components, actual_vocab_size)
    # Keras Dense 레이어 가중치로 이식하기 위해 transpose하여 저장 (shape: actual_vocab_size, n_components)
    svd_weights = svd.components_.T
    
    # 저장 폴더 생성
    os.makedirs("build", exist_ok=True)
    
    # 3. 매핑 정보 및 가중치 저장
    # vocab.json 저장 (단어 -> 인덱스)
    with open("build/vocab.json", "w", encoding="utf-8") as f:
        json.dump(vocab_dict, f, ensure_ascii=False, indent=2)
        
    # idf.json 저장 (각 단어 인덱스에 대응하는 idf 값 리스트)
    # Flutter에서 순서대로 읽을 수 있도록 정렬해서 리스트로 저장
    # vocab_dict의 value(인덱스) 순서대로 idf 값을 배치
    sorted_idf = [0.0] * actual_vocab_size
    for word, idx in vocab_dict.items():
        sorted_idf[idx] = idf_list[idx]
        
    with open("build/idf.json", "w", encoding="utf-8") as f:
        json.dump(sorted_idf, f, ensure_ascii=False, indent=2)
        
    # SVD 가중치 numpy array로 저장
    np.save("build/svd_weights.npy", svd_weights)
    
    # Vectorizer & SVD 객체 저장 (추후 로컬 파이썬 추론 테스트용)
    joblib.dump(vectorizer, "build/vectorizer.joblib")
    joblib.dump(svd, "build/svd.joblib")
    
    print("전처리 파이프라인 빌드 완료 (build/ 폴더에 저장됨)")
    return cleaned_texts, svd_matrix, df['label'].tolist(), vocab_dict, sorted_idf, svd_weights

if __name__ == "__main__":
    build_preprocessing_pipeline("data/sample_dataset.csv")
