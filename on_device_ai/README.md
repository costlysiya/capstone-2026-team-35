# 스스슥 온디바이스(On-device) 텍스트 분류 학습 및 연동 가이드 (Phase 1 데모)

이 프로젝트는 스크린샷 내 추출된 텍스트를 분석하여 4대 카테고리(`SCHEDULE`, `PLACE`, `WISHLIST`, `MEMO`)로 자동 분류하는 온디바이스 경량 AI 환경을 제공합니다.

Phase 1 데모 버전에서는 **TF-IDF 특징 추출 및 Truncated SVD(LSA) 차원 축소 연산을 TFLite 레이어로 내장**하여, Flutter 앱 단에서 행렬곱 코딩 없이 초경량 텍스트 추론 모델을 손쉽게 사용할 수 있도록 설계되었습니다.

---

## 1. 깃(Git)에서 프로젝트 내려받은 후 환경 구축 방법

깃 저장소에서 코드를 내려받은 후, 사용하시는 운영체제(Windows / macOS)에 맞게 환경을 구축해 주세요.

> [!NOTE]
> 깃허브에는 용량이 큰 가상환경 폴더(`venv/`)와 자동 빌드 폴더(`build/`)가 제외되어 있으므로 아래 스크립트를 통해 가상환경을 최초 1회 생성해야 합니다.

### 윈도우 (Windows) 환경
1. PowerShell 또는 터미널을 실행하고 `on_device_ai` 폴더로 이동합니다.
2. 아래의 환경 구축 스크립트를 실행합니다:
   ```powershell
   .\setup_env.ps1
   ```
   *만약 권한 에러(ExecutionPolicy)가 발생할 경우 아래 명령어로 실행해 주세요:*
   ```powershell
   PowerShell -ExecutionPolicy Bypass -File .\setup_env.ps1
   ```

### 맥 (macOS / Linux) 환경
1. 터미널을 실행하고 `on_device_ai` 폴더로 이동합니다.
2. 아래 스크립트에 실행 권한을 부여하고 실행합니다:
   ```bash
   chmod +x setup_env.sh
   ./setup_env.sh
   ```

---

## 2. 모델 학습 및 TFLite 변환 방법

가상환경 세팅이 완료되면 아래 명령어로 텍스트를 학습시키고 TFLite 파일로 변환을 수행합니다.

### 윈도우 (Windows)
```powershell
.\venv\Scripts\python.exe src/train.py
```

### 맥 (macOS / Linux)
```bash
./venv/bin/python src/train.py
```

### 실행 후 산출물 (`build/` 폴더 내에 생성됨)
- `classifier_demo.tflite`: 모바일 탑재용 TFLite 모델 파일 (FP16 양자화, 크기: 약 46KB)
- `vocab.json`: 어절 토큰화 매핑 단어 사전 파일 (`word` -> `index`)
- `idf.json`: 각 단어별 IDF 가중치 배열
- `label_map.json`: 출력 인덱스 정수와 카테고리 라벨의 매핑 메타데이터

---

## 3. 로컬 TFLite 추론 검증 (시뮬레이션)

변환 완료된 TFLite 모델이 작동하는지 가상 문장들로 간편하게 로컬 테스트를 돌려볼 수 있습니다.

### 윈도우 (Windows)
```powershell
.\venv\Scripts\python.exe src/inference_test.py
```

### 맥 (macOS / Linux)
```bash
./venv/bin/python src/inference_test.py
```

---

## 4. Flutter(Dart) 앱 내 모델 서빙 및 연동 방법 (팀원 배포용 가이드)

모바일 개발 담당(공다은 팀원 등)이 Flutter 앱에서 학습된 `classifier_demo.tflite`를 로드하여 서빙하기 위한 상세 예시 코드 가이드입니다.

### (1) 플러그인 설정 (`pubspec.yaml`)
추론용 패키지와 에셋 경로를 추가해 줍니다.

```yaml
dependencies:
  flutter:
    sdk: flutter
  tflite_flutter: ^0.10.0 # 혹은 최신 버전

flutter:
  assets:
    - assets/classifier_demo.tflite
    - assets/vocab.json
    - assets/idf.json
    - assets/label_map.json
```
*(주의: 파이썬 빌드가 끝난 후 `build/` 폴더 내의 산출물 파일들을 Flutter 프로젝트의 `assets/` 디렉토리로 직접 복사해주어야 합니다.)*

### (2) Dart 기반 TF-IDF 및 추론 연동 클래스 구현
아래 코드를 복사하여 Dart 코드로 이식해 사용하세요. 파이썬 전처리와 동일한 메커니즘으로 동작하도록 구현되었습니다.

```dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class OnDeviceTextClassifier {
  Interpreter? _interpreter;
  Map<String, int>? _vocab;
  List<double>? _idf;
  Map<int, String>? _labelMap;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  // 1. 에셋 로드 및 TFLite 인터프리터 초기화
  Future<void> initialize() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/classifier_demo.tflite');
      
      final vocabStr = await rootBundle.loadString('assets/vocab.json');
      _vocab = Map<String, int>.from(json.decode(vocabStr));
      
      final idfStr = await rootBundle.loadString('assets/idf.json');
      _idf = List<double>.from(json.decode(idfStr));
      
      final labelMapStr = await rootBundle.loadString('assets/label_map.json');
      final tempMap = Map<String, dynamic>.from(json.decode(labelMapStr));
      _labelMap = tempMap.map((key, value) => MapEntry(int.parse(key), value.toString()));
      
      _isInitialized = true;
      print("온디바이스 분류 모델 로드 및 초기화 성공!");
    } catch (e) {
      print("초기화 실패: $e");
    }
  }

  // 2. 한국어 텍스트 전처리 및 어절 TF-IDF 계산 (파이썬 clean_text & Vectorizer 이식)
  List<double> _preprocessToTfidf(String text) {
    if (!_isInitialized) return [];

    // 가. 특수문자 제거 및 소문자 정제
    final cleaned = text.replaceAll(RegExp(r'[^가-힣a-zA-Z0-9\s]'), ' ')
                        .replaceAll(RegExp(r'\s+'), ' ')
                        .trim()
                        .toLowerCase();
    
    // 나. 어절 단위 토큰화
    final tokens = cleaned.split(' ');
    
    // 다. 단어 빈도(TF) 딕셔너리 구축
    final tfMap = <String, int>{};
    for (var token in tokens) {
      if (_vocab!.containsKey(token)) {
        tfMap[token] = (tfMap[token] ?? 0) + 1;
      }
    }
    
    // 라. 단어 사전에 기반해 TF-IDF 가중치 연산
    final vocabSize = _vocab!.length;
    final tfidfVector = List<double>.filled(vocabSize, 0.0);
    
    tfMap.forEach((token, count) {
      final idx = _vocab![token]!;
      tfidfVector[idx] = count * _idf![idx];
    });
    
    // 마. L2 정규화 (L2 Normalization)
    double sumOfSquares = 0.0;
    for (var val in tfidfVector) {
      sumOfSquares += val * val;
    }
    double norm = sqrt(sumOfSquares);
    
    if (norm > 0) {
      for (int i = 0; i < vocabSize; i++) {
        tfidfVector[i] = tfidfVector[i] / norm;
      }
    }
    
    return tfidfVector;
  }

  // 3. TFLite 기반 추론 실행
  String classify(String rawText) {
    if (!_isInitialized || _interpreter == null) {
      return "모델이 초기화되지 않았습니다.";
    }

    // 전처리 완료된 1D 벡터 획득
    final tfidfVector = _preprocessToTfidf(rawText);
    if (tfidfVector.isEmpty) return "MEMO"; // 폴백 기본값

    // 모델 입력 형상에 맞춘 다차원 리스트 구성 [1, vocabSize]
    final input = [tfidfVector];
    
    // 출력 버퍼 준비: [1, 4] (4대 카테고리 확률값)
    final output = List<double>.filled(4, 0.0).reshape([1, 4]);
    
    // TFLite 실행
    _interpreter!.run(input, output);
    
    final probs = output[0] as List<double>;
    
    // 최댓값 인덱스(ArgMax) 찾기
    int maxIdx = 0;
    double maxProb = -1.0;
    for (int i = 0; i < probs.length; i++) {
      if (probs[i] > maxProb) {
        maxProb = probs[i];
        maxIdx = i;
      }
    }
    
    // 예측 라벨 리턴
    return _labelMap?[maxIdx] ?? "MEMO";
  }

  void dispose() {
    _interpreter?.close();
  }
}
```
