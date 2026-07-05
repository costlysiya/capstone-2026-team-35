# soseang_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.



# 🌱 소생 앱 (soseang_app) - 모바일 프론트엔드 파트

> **스스슥 사진 및 스크린샷 정보 추출 및 관리 서비스**
> 본 저장소는 소생 앱의 **모바일 애플리케이션(Flutter)** 소스코드가 포함된 `feature/mobile-app` 브랜치입니다. 외부 서버를 거치지 않고 사용자 기기 내부에서 안전하게 개인정보를 처리하는 **온디바이스(On-Device) OCR** 엔진 및 초안 편집 UI가 구현되어 있습니다.

---

## 📅 현재 개발 진척도 (중간보고서 기점)

- [x] **1주차: 프로토타입 환경 구축** (로컬 디렉토리 초기화 및 갤러리 연동 완료)
- [x] **2주차: 온디바이스 AI OCR 엔진 이식** (구글 ML Kit 한글 텍스트 인식 엔진 완벽 연동)
- [x] **3주차: 정보 파싱 및 초안 카드 UI 구현** (텍스트 분리 알고리즘 탑재 및 수정 가능한 텍스트 필드 바인딩 완료)
- [ ] **4주차~ (예정): 카테고리 자동 분류 연동** (장소, 위시, 메모, 일정 분류 엔진 모델 결합 및 로컬 보관함 DB 구축)

---

## ✨ 핵심 기능 (Key Features)

1. **온디바이스(On-Device) OCR 분석**
   - 구글의 `google_mlkit_text_recognition` 엔진을 활용하여 오프라인(비행기 모드) 상태에서도 스크린샷 내 한글/영어/숫자를 완벽하게 추출합니다.
   - 외부 서버로 이미지가 전송되지 않아 사용자의 개인정보 및 금융/메모 스크린샷을 완벽하게 보호합니다.

2. **텍스트 자동 분리 파싱 (Draft Parser)**
   - 추출된 날것의 텍스트(Raw Text) 중 **첫 번째 줄은 [📌 제목]**, **나머지 줄은 [📝 내용]**으로 자동 분류하여 정돈합니다.

3. **편집 가능한 초안 카드 UI (Editable Draft Card)**
   - AI가 잘못 인식한 잔오타(`항미` -> `항목` 등)를 사용자가 화면에서 직접 텍스트 필드를 터치하여 수정하고 보정할 수 있는 유연한 검토 창을 제공합니다.

---

## 📂 주요 파일 및 디렉토리 구조 (Directory Structure)

```text
soseang_app/
├── lib/
│   ├── main.dart                      # ⭐ 앱의 메인 UI, 상태 관리(Riverpod), 구글 ML Kit OCR 로직 총괄
│   └── core/
│       └── storage/
│           └── app_storage.dart       # 앱 실행 시 기기 내 로컬 보안 디렉토리 초기화 담당
│
└── android/
    └── app/
        ├── src/main/AndroidManifest.xml # ⭐ 구글 온디바이스 AI 모델 자동 다운로드를 위한 메타데이터 설정
        └── build.gradle.kts           # ⭐ 최소 사양 변경(minSdk=21) 및 한글 OCR 원격 의존성 패키지(Dependencies) 추가
```

 ## 🛠️ 초보자를 위한 전체 개발 환경 설정 및 실행 가이드 (Step-by-Step Setup)
이 프로젝트를 자신의 컴퓨터 환경에 처음부터 다운로드하고 실제 스마트폰에서 구동하기까지의 전 과정 상세 가이드입니다.

## 1단계: 필수 프로그램 설치하기
1. Flutter SDK 설치

    - Flutter 공식 홈페이지에서 본인의 운영체제(Windows/Mac)에 맞는 최신 안정(Stable) 버전을 다운로드합니다.

    - 다운로드한 압축 파일을 적절한 경로(예: C:\src\flutter)에 풀고, 컴퓨터 환경 변수(Path)에 flutter\bin 경로를 등록합니다.

2. Android Studio 및 SDK 설치

    - Android Studio 공식 홈페이지에서 다운로드 후 설치를 진행합니다.

    - 설치 과정 중 구성 요소 선택 창에서 Android SDK, Android SDK Command-line Tools, Android Virtual Device 항목을 반드시 체크하여 함께 설치합니다.

3. VS Code (코드 편집기) 설정

    - VS Code 설치 후, 왼쪽 확장(Extensions, Ctrl+Shift+X) 탭에서 Flutter와 Dart 플러그인을 검색하여 인스톨합니다.

## 2단계: 설치 상태 검증하기
터미널(CMD 또는 PowerShell)을 열고 아래 명령어를 입력하여 모든 개발 환경이 올바르게 잡혔는지 최종 점검합니다.

Bash
flutter doctor
만약 [X] 표시가 뜬 항목이 있다면 화면의 안내 메시지에 따라 추가 설치를 진행하거나 라이선스 동의 명령어(flutter doctor --android-licenses)를 실행해 줍니다.

## 3단계: 소스코드 다운로드 및 브랜치 이동하기
1. 프로젝트를 저장할 폴더에서 터미널을 열고 팀 원격 저장소를 클론(복제)합니다.

Bash
git clone <팀_깃허브_레포지토리_주소>
cd soseang_app

2. 다은이가(..ㅎ) 구글 AI OCR을 연동해 둔 모바일 앱 전용 작업 브랜치(feature/mobile-app)로 방을 이동합니다.

Bash
git fetch origin
git checkout feature/mobile-app

## 4단계: 의존성 패키지 다운로드
프로젝트 빌드에 필요한 외부 라이브러리들(Google ML Kit, Riverpod 상태관리, Image Picker 등)을 컴퓨터 환경에 맞게 로컬 캐시에 내려받습니다.

Bash
flutter pub get

## 5단계: 스마트폰 개발자 모드 활성화 및 연결
1. 스마트폰 설정 (안드로이드 기준)

    - 기기의 [설정] ➡️ [휴대전화 정보] ➡️ [소프트웨어 정보] 메뉴로 진입합니다.

    - [빌드 번호] 항목을 연속으로 7번 빠르게 다다다닥 터치하여 개발자 모드를 활성화합니다.

    - 다시 [설정] 첫 화면으로 돌아와 맨 아래 새로 생긴 [개발자 옵션] 메뉴를 클릭합니다.

    - 화면을 조금 내려 나오는 [USB 디버깅] 토글 스위치를 찾아서 [켜짐]으로 변경합니다.

2. PC와 디바이스 연결

    - 데이터 전송용 USB 케이블을 이용해 스마트폰과 컴퓨터를 연결합니다.

    - 스마트폰 화면에 "USB 디버깅을 허용하시겠습니까?"라는 안드로이드 보안 팝업이 뜨면 [이 컴퓨터에서 항상 허용] 또는 [확인]을 눌러줍니다.

## 6단계: 대망의 앱 실행하기
1. 터미널 창에 아래 명령어를 입력해 PC에 스마트폰 기기가 정상 인식되었는지 고유 ID를 확인합니다.

Bash
flutter devices

2. 확인된 디바이스 ID를 대입하여 스마트폰으로 앱을 실시간 조립 및 전송하여 실행합니다.

Bash
flutter run -d <본인의_디바이스_ID>

최초 빌드 시에는 구글 온디바이스 NDK 부품 및 한글 OCR 팩을 네이티브단에 빌드하므로 몇 분 정도 시간이 소요될 수 있습니다. 정상 구동되면 스마트폰에 '소생 앱'이 자동으로 켜집니다.
