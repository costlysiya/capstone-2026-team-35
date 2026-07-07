# inference_test.py
import json
import numpy as np
import tensorflow as tf
import os
from preprocess import clean_text

def manual_tfidf_vectorizer(text, vocab, idf):
    """
    Scikit-learn의 TfidfVectorizer와 호환되는 수동 TF-IDF 계산 함수.
    이 로직은 Flutter (Dart) 단에서 그대로 구현되어 사용될 핵심 레퍼런스입니다.
    """
    # 1. 텍스트 정제 및 토큰화 (공백 분할)
    cleaned = clean_text(text)
    tokens = cleaned.split()
    
    # 2. 빈도(TF) 계산
    tf_dict = {}
    for token in tokens:
        if token in vocab:
            tf_dict[token] = tf_dict.get(token, 0) + 1
            
    # 3. TF-IDF 벡터 생성
    vocab_size = len(vocab)
    tfidf_vector = np.zeros(vocab_size, dtype=np.float32)
    
    for token, count in tf_dict.items():
        idx = vocab[token]
        # Scikit-learn 기본 TfidfVectorizer 공식: tf * idf (여기서 tf는 단순 출현 빈도)
        tfidf_vector[idx] = count * idf[idx]
        
    # 4. L2 정규화 (Normalization)
    norm = np.linalg.norm(tfidf_vector)
    if norm > 0:
        tfidf_vector = tfidf_vector / norm
        
    return tfidf_vector

def run_tflite_inference(test_texts):
    # build 폴더에 리소스가 있는지 확인
    if not os.path.exists("build/classifier_demo.tflite"):
        print("에러: TFLite 모델 파일이 존재하지 않습니다. 먼저 train.py를 실행하세요.")
        return
        
    # 1. 리소스 파일 로드
    with open("build/vocab.json", "r", encoding="utf-8") as f:
        vocab = json.load(f)
    with open("build/idf.json", "r", encoding="utf-8") as f:
        idf = json.load(f)
    with open("build/label_map.json", "r", encoding="utf-8") as f:
        label_map = json.load(f)
        
    # 2. TFLite 인터프리터 로드
    interpreter = tf.lite.Interpreter(model_path="build/classifier_demo.tflite")
    interpreter.allocate_tensors()
    
    # 입력/출력 텐서 정보 획득
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    
    print("\n========== TFLite 모델 추론 테스트 ==========")
    print(f"입력 텐서 형상: {input_details[0]['shape']}")
    print(f"출력 텐서 형상: {output_details[0]['shape']}")
    
    for text in test_texts:
        # 수동 TF-IDF 계산 (Dart 이식용 로직 검증)
        input_vector = manual_tfidf_vectorizer(text, vocab, idf)
        # 배치 차원 추가 [1, vocab_size]
        input_data = np.expand_dims(input_vector, axis=0)
        
        # 인터프리터에 입력 설정
        interpreter.set_tensor(input_details[0]['index'], input_data)
        
        # 모델 추론 실행
        interpreter.invoke()
        
        # 결과 획득
        output_data = interpreter.get_tensor(output_details[0]['index'])[0]
        
        # 가장 높은 확률값의 클래스 선택
        predicted_idx = np.argmax(output_data)
        confidence = output_data[predicted_idx]
        predicted_label = label_map[str(predicted_idx)]
        
        print(f"\n입력 문장: \"{text}\"")
        print(f"-> 예측 결과: {predicted_label} (신뢰도: {confidence:.2%})")
        print(f"   [상세 확률: SCHEDULE={output_data[0]:.2%}, PLACE={output_data[1]:.2%}, WISHLIST={output_data[2]:.2%}, MEMO={output_data[3]:.2%}]")

if __name__ == "__main__":
    # 테스트용 가상 스크린샷 텍스트 4종
    test_samples = [
        "선물하기 바코드 유효기간이 2026/12/31 까지 입니다. 만료 전에 매장에서 사용 하시기 바랍니다.",
        "인스타 핫플 성수 카페 주소는 서울특별시 성동구 연무장 5길 입니다. 디저트가 진짜 맛있음",
        "쿠팡에서 파는 무선 이어폰 특가 59000원 무료 배송중인데 살까말까 고민된다",
        "오늘 해야할 일 정리하기. 1. 헬스장가서 하체운동 2. 자격증 시험 원서 접수하기 3. 개발 회의 참석"
    ]
    run_tflite_inference(test_samples)
