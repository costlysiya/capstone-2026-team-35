import os
import csv
import pandas as pd
import easyocr
from tqdm import tqdm

# 1. 설정 정보
DATASET_PATH = "/Users/chaeyoon/Library/CloudStorage/GoogleDrive-costlysiya@gmail.com/내 드라이브/졸과"
OUTPUT_CSV = "./dataset.csv"

# 카테고리별 라벨 매핑 (착수보고서 기준 4대 카테고리)
LABEL_MAP = {
    "SCHEDULE": 0,
    "PLACE": 1,
    "WISHLIST": 2,
    "MEMO": 3
}

def main():
    # OCR 엔진 초기화 (한글 'ko', 영어 'en' 동시 지원)
    print("🤖 EasyOCR 엔진을 로드 중입니다...")
    reader = easyocr.Reader(['ko', 'en'], gpu=True) # GPU가 있다면 gpu=True 사용

    dataset_records = []
    processed_files = set()
    deleted_files_count = 0

    # 2. 기존 dataset.csv가 존재하면 기존 데이터를 로드하여 이미 처리된 파일 목록 추출 (증분 빌드 및 삭제 반영)
    if os.path.exists(OUTPUT_CSV):
        try:
            existing_df = pd.read_csv(OUTPUT_CSV)
            temp_records = existing_df.dropna(subset=['file_path']).to_dict('records')
            
            # 실제로 파일이 존재하는지 검증하여 삭제된 파일은 dataset_records에서 제외
            for item in temp_records:
                full_path = os.path.join(DATASET_PATH, item['file_path'])
                if os.path.exists(full_path):
                    dataset_records.append(item)
                    processed_files.add(item['file_path'])
                else:
                    deleted_files_count += 1
                    
            print(f"ℹ️ 기존 CSV 파일 발견: {len(processed_files)}개의 기존 파일 유지 (삭제된 파일 {deleted_files_count}개 자동 정리됨)")
        except Exception as e:
            print(f"⚠️ 기존 CSV 파일을 읽는 중 오류가 발생하여 새로 빌드합니다: {e}")
            dataset_records = []
            processed_files = set()
            deleted_files_count = 0

    # 3. 폴더 탐색
    print("📁 폴더 탐색을 시작합니다...")
    new_files_processed = 0
    
    for category_name, label in LABEL_MAP.items():
        category_dir = os.path.join(DATASET_PATH, category_name)
        if not os.path.exists(category_dir):
            print(f"⚠️ 경고: {category_name} 폴더를 찾을 수 없어 건너뜁니다.")
            continue
            
        print(f"📂 카테고리 처리 중: {category_name} (라벨: {label})")
        files = [f for f in os.listdir(category_dir) if f.lower().endswith(('.png', '.jpg', '.jpeg'))]
        
        for file in tqdm(files, desc=category_name):
            image_path = os.path.join(category_dir, file)
            relative_path = os.path.join(category_name, file)
            
            # 이미 처리된 파일은 스킵 (증분 처리 핵심)
            if relative_path in processed_files:
                continue
                
            try:
                # 4. 로컬 OCR 실행
                results = reader.readtext(image_path, detail=0)
                extracted_text = " ".join(results).strip()
                
                # 5. 레코드 추가
                dataset_records.append({
                    "file_path": relative_path,
                    "label": label,
                    "extracted_text": extracted_text
                })
                new_files_processed += 1
            except Exception as e:
                print(f"\n❌ 에러 발생 - 파일: {file}, 내용: {e}")

    # 6. CSV 저장
    if new_files_processed > 0 or deleted_files_count > 0 or not os.path.exists(OUTPUT_CSV):
        df = pd.DataFrame(dataset_records)
        df.to_csv(OUTPUT_CSV, index=False, encoding="utf-8-sig")
        print(f"\n✅ 데이터셋 업데이트 완료! 신규 추가: {new_files_processed}개, 자동 삭제 정리: {deleted_files_count}개 -> 저장 위치: {OUTPUT_CSV}")
    else:
        print("\n✨ 새로 추가되거나 삭제된 이미지 파일이 없어 작업을 종료합니다. (데이터셋 최신 상태)")

if __name__ == "__main__":
    main()
