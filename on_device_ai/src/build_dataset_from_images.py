# build_dataset_from_images.py
import os
import csv
import glob

# easyocr 라이브러리 사용 (pip install easyocr torch torchvision 필요)
# easyocr은 첫 실행 시 한국어/영어 가중치 모델을 자동으로 다운로드합니다.
try:
    import easyocr
except ImportError:
    print("\n[!] 에러: easyocr 라이브러리가 설치되어 있지 않습니다.")
    print("이미지 기반 데이터셋 자동 구축을 위해서는 아래 패키지를 가상환경 활성화 상태에서 추가로 설치해 주셔야 합니다:")
    print("  .\\venv\\Scripts\\pip.exe install easyocr torch torchvision --extra-index-url https://download.pytorch.org/whl/cpu")
    print("  (또는 Mac: ./venv/bin/pip install easyocr torch torchvision)\n")
    exit(1)

def build_dataset(image_root_dir, output_csv_path):
    print("EasyOCR 판독기(Korean, English) 로딩 중... (처음 실행 시 가중치 다운로드에 시간이 걸릴 수 있습니다)")
    # CPU 기반으로 가볍게 로드
    reader = easyocr.Reader(['ko', 'en'], gpu=False)
    
    # 4대 카테고리 정의
    categories = ['SCHEDULE', 'PLACE', 'WISHLIST', 'MEMO']
    
    dataset = []
    
    # 이미지를 넣을 기본 구조 생성
    for cat in categories:
        os.makedirs(os.path.join(image_root_dir, cat), exist_ok=True)
        
    print(f"\n[안내] {image_root_dir} 하위의 폴더들(SCHEDULE, PLACE, WISHLIST, MEMO)에 분류할 사진들을 배치해 주세요.")
    
    has_images = False
    for category in categories:
        category_dir = os.path.join(image_root_dir, category)
            
        # 지원 이미지 확장자
        image_extensions = ['*.jpg', '*.jpeg', '*.png', '*.webp', '*.bmp']
        image_paths = []
        for ext in image_extensions:
            image_paths.extend(glob.glob(os.path.join(category_dir, ext)))
            image_paths.extend(glob.glob(os.path.join(category_dir, ext.upper())))
            
        if len(image_paths) > 0:
            has_images = True
            
        print(f"\n[{category}] 폴더에서 {len(image_paths)}개의 이미지를 발견했습니다.")
        
        for idx, img_path in enumerate(image_paths):
            print(f"  ({idx+1}/{len(image_paths)}) {os.path.basename(img_path)} OCR 판독 중...")
            try:
                # OCR 실행 (텍스트 라인 영역을 단순 텍스트 리스트로 추출)
                result = reader.readtext(img_path, detail=0)
                extracted_text = " ".join(result)
                
                # 빈 텍스트 무시
                if extracted_text.strip():
                    dataset.append({
                        'text': extracted_text.strip(),
                        'label': category
                    })
                    print(f"  -> 추출 성공! ({len(extracted_text)} 글자)")
                else:
                    print(f"  -> 판독 실패 (이미지 내 인식 가능한 텍스트가 없습니다)")
            except Exception as e:
                print(f"  -> 에러 발생: {e}")
                
    if not has_images:
        print(f"\n[안내] {image_root_dir} 내 각 카테고리 폴더에 이미지가 존재하지 않습니다.")
        print(f"  예시: {image_root_dir}/SCHEDULE/ 기프티콘.jpg 파일을 넣은 후 스크립트를 재실행해 주세요.")
        return

    # CSV 저장
    os.makedirs(os.path.dirname(output_csv_path), exist_ok=True)
    with open(output_csv_path, 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['text', 'label']) # 헤더
        for data in dataset:
            writer.writerow([data['text'], data['label']])
            
    print(f"\n========== 데이터셋 빌드 완료! ==========")
    print(f"총 {len(dataset)}개의 텍스트 데이터가 {output_csv_path}에 저장되었습니다.")
    print("이제 아래 명령어로 분류기 학습을 시작하실 수 있습니다:")
    print("  .\\venv\\Scripts\\python.exe src/train.py")

if __name__ == "__main__":
    # 기본 이미지 저장 위치: data/images/
    # 기본 출력 CSV 위치: data/train_dataset.csv
    build_dataset("data/images", "data/train_dataset.csv")
