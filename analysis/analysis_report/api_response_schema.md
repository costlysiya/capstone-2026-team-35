# 📄 [백엔드] 이미지 분석 API 응답 데이터 규격서 (프론트엔드 연동용)

이 문서는 SSS 앱의 서버에서 반환하는 분석 결과 JSON 데이터 구조와 각 카테고리별 상세 필드를 설명합니다.

---

## 1. 최상위 응답 구조 (`AnalyzeResponse`)

서버에서 응답하는 공통 JSON 최상위 데이터 구조입니다.

```json
{
  "id": 42,
  "type": "SCHEDULE",
  "confidence": 0.95,
  "status": "DRAFT",
  "missing_fields": [],
  "masked_info": [
    {
      "original": "1234-****-****-1234",
      "type": "CARD"
    }
  ],
  "fields": { ... }
}
```

| 필드명 | 타입 | 설명 |
| :--- | :--- | :--- |
| `id` | `int` \| `null` | DB에 저장된 결과 PK (실패 시 `null`) |
| `type` | `string` | 4대 대분류 (`SCHEDULE`, `PLACE`, `WISHLIST`, `MEMO`) |
| `confidence` | `float` | 서버 신뢰도 점수 (`0.0` ~ `1.0`) |
| `status` | `string` | 데이터 상태 (`DRAFT`: 자동채움 완료, `NEEDS_EDIT`: 필수값 누락되어 수정 필요, `CONFIRMED`: 사용자 승인 완료) |
| `missing_fields` | `list[string]` | 추출되지 못한 필수 필드 목록 (수정 필요한 항목 안내용) |
| `masked_info` | `list[object]` | 마스킹되어 전송된 원본 민감정보의 유형 분석 결과 (로컬 저장 판단용) |
| `fields` | `object` | **타입별 추출된 상세 데이터 (핵심)** |

---

## 2. 타입별 `fields` 상세 데이터 구조

`type` 값에 따라 `fields` 내부의 구조와 오토필(자동 보강) 값이 달라집니다.

---

### ① 📅 `SCHEDULE` (일정 · 기프티콘 · 구독 · 티켓 등)

서버에서 `sub_type`을 자동 판별하여 캘린더 등록 및 알림에 필요한 필드를 자동으로 보강해 줍니다.

```json
{
  "sub_type": "GIFTICON",
  "title": "스타벅스 아이스 아메리카노 T",
  "start_at": null,
  "expires_at": "2026-08-15",
  "location": null,
  "barcode_number": "1234 5678 9012",
  "memo": "선물받은 쿠폰",
  
  "keep_photo": true,
  "calendar_type": "EXPIRY",
  "reminder_days": [7, 3, 1]
}
```

* **`sub_type` 종별 목록:**
  * `GIFTICON` (기프티콘/쿠폰): `keep_photo: true` (바코드 사진 보관), `calendar_type: "EXPIRY"`, `reminder_days: [7, 3, 1]`
  * `SUBSCRIPTION` (구독 서비스): `keep_photo: false`, `calendar_type: "RENEWAL"`, `reminder_days: [30, 7, 1]`, `recurrence: "매월"`
  * `APPOINTMENT` (일반 약속/미팅): `keep_photo: false`, `calendar_type: "EVENT"`, `reminder_days: [1]`
  * `TICKET` (티켓/예약): `keep_photo: true` (예매번호 보관), `calendar_type: "EVENT"`, `reminder_days: [3, 1]`
  * `DEADLINE` (마감일/시험): `calendar_type: "DEADLINE"`, `reminder_days: [14, 7, 3, 1]`
  * `DELIVERY` (택배/배송): `calendar_type: "DELIVERY"`, `reminder_days: [1]`

---

### ② 📍 `PLACE` (장소 · 맛집 · 여행지 등)

지도 연동 및 장소 저장을 위한 필드입니다.

```json
{
  "name": "을지다락",
  "category": "파스타/양식",
  "address": "서울 중구 수표로 48-16 3층",
  "region": "서울 중구",
  "memo": "오므라이스 맛집, 웨이팅 있음",
  
  "keep_photo": false,
  "map_ready": true
}
```

* **주요 자동 생성 필드:**
  * `map_ready` (`bool`): `address` 또는 `region`이 추출되어 지도 버튼을 바로 띄울 수 있는지 여부
  * `category` (`string`): 없으면 기본값 `"기타"`
  * `keep_photo` (`bool`): 장소 캡처본은 용량을 줄이기 위해 기본 `false` (사진 삭제 권장)

---

### ③ 🛍️ `WISHLIST` (쇼핑 · 위시리스트)

상품 가격 정규화 및 상품 저장을 위한 필드입니다.

```json
{
  "title": "나이키 에어맥스 90",
  "price_amount": 129000.0,
  "brand_or_store": "나이키 공식 홈페이지",
  "option": "270mm / 화이트",
  "url": "https://www.nike.com/kr/...",
  
  "keep_photo": true
}
```

* **주요 자동 생성 필드:**
  * `price_amount` (`float` \| `null`): 텍스트의 `₩129,000원` 같은 문자열에서 숫자만 자동 정규화 추출
  * `keep_photo` (`bool`): 사고 싶은 상품의 원본 캡처 이미지 보관을 위해 기본 `true`

---

### ④ 📝 `MEMO` (일반 메모 · 정보)

일반 텍스트 정리 및 제목 자동 생성 필드입니다.

```json
{
  "title": "오늘 회의 내용 요약",
  "body": "오늘 회의 내용 요약: 1. 프론트엔드 작업 금요일까지 완료. 2. 백엔드는 API 문서 최신화할 것.",
  "tags": ["회의", "업무"],
  
  "keep_photo": false
}
```

* **주요 자동 생성 필드:**
  * `title` (`string`): OCR 텍스트에 제목이 명시되지 않은 경우 `body` 앞 30자를 따서 자동 제목 생성
  * `keep_photo` (`bool`): 텍스트 메모이므로 용량 절약을 위해 기본 `false`

---

## 3. 🔒 마스킹 정보 구조화 (`masked_info`)

앱에서 개인정보 마스킹 처리를 해서 서버로 보냈을 때, 원본 토큰의 종류를 분석해 응답해 줍니다.

```json
"masked_info": [
  { "original": "1234-1234-1234-1234", "type": "CARD" },
  { "original": "990101-1234567", "type": "SSN" },
  { "original": "010-1234-5678", "type": "PHONE" },
  { "original": "8801234567890", "type": "BARCODE" }
]
```

* **`type` 종류:** `CARD` (카드번호), `SSN` (주민번호), `PHONE` (전화번호), `BARCODE` (바코드), `OTHER` (기타)
* **프론트 활용:** 이 데이터를 보고 "원본 카드번호/전화번호를 사용자 기기(로컬 DB)에 암호화하여 저장하시겠습니까?" 팝업을 띄우는 용도로 활용할 수 있습니다.

---

## 💡 프론트엔드 개발자 팁 요약
1. **화면 분기**: `type` (`SCHEDULE`, `PLACE`, `WISHLIST`, `MEMO`)에 따라 화면 탭이나 아이콘을 다르게 렌더링하세요.
2. **원본 사진 삭제 여부**: 서버 응답의 `fields.keep_photo`가 `false`이면 원본 스크린샷 이미지를 단말 디바이스 용량 절약을 위해 자동 삭제 처리해도 됩니다.
3. **캘린더 연동**: `SCHEDULE` 타입일 때 `calendar_type`과 `reminder_days` 배열 값을 활용해 디바이스 캘린더 등록 알림 옵션을 기본 선택 상태로 구성하세요.
