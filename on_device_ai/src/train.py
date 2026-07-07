# train.py
import os
import json
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models, optimizers
from preprocess import build_preprocessing_pipeline

# 라벨 매핑 정의
LABEL_MAP = {
    'SCHEDULE': 0,
    'PLACE': 1,
    'WISHLIST': 2,
    'MEMO': 3
}
INV_LABEL_MAP = {v: k for k, v in LABEL_MAP.items()}

def train_and_convert():
    # 1. 데이터 및 전처리 가중치 획득
    data_path = "data/train_dataset.csv" if os.path.exists("data/train_dataset.csv") else "data/sample_dataset.csv"
    print(f"사용할 데이터셋 경로: {data_path}")
    cleaned_texts, svd_matrix, labels, vocab_dict, idf_list, svd_weights = build_preprocessing_pipeline(
        data_path=data_path,
        vocab_size=1000,
        svd_components=100
    )
    
    vocab_size = len(vocab_dict)
    n_components = svd_weights.shape[1]
    
    # 라벨을 정수 인덱스로 변환
    y_train = np.array([LABEL_MAP[l] for l in labels])
    
    # TF-IDF 벡터를 직접 모델에 입력하기 위해 전체 데이터셋에 대한 TF-IDF 매트릭스 복원
    # (preprocess.py에서 저장한 vectorizer를 로드하여 사용)
    import joblib
    vectorizer = joblib.load("build/vectorizer.joblib")
    x_train_tfidf = vectorizer.transform(cleaned_texts).toarray()
    
    print(f"학습 데이터 형상: X={x_train_tfidf.shape}, Y={y_train.shape}")
    
    # 2. Keras 모델 정의 (SVD 가중치를 1층 Dense에 고정 내장)
    # 입력: TF-IDF 벡터 (vocab_size 차원)
    inputs = layers.Input(shape=(vocab_size,), name="tfidf_input")
    
    # 1층 Dense: SVD 차원 축소 역할 (bias 미사용, 학습 불가 설정)
    # Weights shape: (vocab_size, n_components)
    svd_layer = layers.Dense(
        n_components, 
        use_bias=False, 
        trainable=False, 
        name="svd_projection"
    )
    
    # 모델 빌드 전 가중치 형상 맞추기 위해 레이어 선언 후 임시 할당
    projection = svd_layer(inputs)
    svd_layer.set_weights([svd_weights])
    
    # 은닉층 및 출력층 (이 레이어들만 학습됨)
    x = layers.Dense(32, activation='relu', name="dense_1")(projection)
    x = layers.Dropout(0.2)(x)
    outputs = layers.Dense(4, activation='softmax', name="softmax_output")(x)
    
    model = models.Model(inputs=inputs, outputs=outputs, name="SVD_Text_Classifier")
    
    model.compile(
        optimizer=optimizers.Adam(learning_rate=0.01),
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )
    
    model.summary()
    
    # 3. 모델 학습
    print("모델 학습 시작...")
    # 데모용 샘플 데이터이므로 간단히 100 Epochs 진행
    history = model.fit(
        x_train_tfidf, 
        y_train, 
        epochs=100, 
        batch_size=8, 
        validation_split=0.2, 
        verbose=1
    )
    
    # 4. 모델 저장
    os.makedirs("build", exist_ok=True)
    model.save("build/classifier_demo.keras")
    print("Keras 포맷으로 모델 저장 완료.")
    
    # 5. TFLite 변환
    print("TFLite 모델 변환 진행 중...")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    
    # 소형 TFLite 최적화를 위해 FP16 양자화 적용 (데모 수준에서도 기본 적용)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    
    tflite_model = converter.convert()
    
    # TFLite 파일 쓰기
    tflite_path = "build/classifier_demo.tflite"
    with open(tflite_path, "wb") as f:
        f.write(tflite_model)
        
    print(f"TFLite 모델 변환 완료: {tflite_path} (크기: {os.path.getsize(tflite_path) / 1024:.2f} KB)")
    
    # 라벨 맵 저장
    with open("build/label_map.json", "w", encoding="utf-8") as f:
        json.dump(INV_LABEL_MAP, f, ensure_ascii=False, indent=2)
        
    print("라벨 메타데이터 저장 완료.")

if __name__ == "__main__":
    train_and_convert()
