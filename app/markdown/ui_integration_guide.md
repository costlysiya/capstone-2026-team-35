# 📱 소생 앱 — 프론트엔드 UI 렌더링 가이드

본 문서는 LLM이 반환하는 다양한 필드(가변 필드)를 Flutter 앱에서 효율적이고 깔끔하게 렌더링하기 위한 가이드입니다.

## 💡 핵심 전략: 고정 UI + 동적 Key-Value 렌더링

타입마다 필드가 다르고, 같은 타입이라도 GPT 응답에 따라 필드 유무가 달라집니다. 따라서 모든 필드에 대해 UI 칸을 미리 만들어두면 빈칸이 너무 많아집니다. 이를 해결하기 위해 **핵심 필드만 고정 배치하고, 나머지는 자동으로 그려지는 구조**를 채택합니다.

---

## 👨‍💻 백엔드(서버) 역할

백엔드는 **현재 JSON 응답 구조를 그대로 유지**합니다. 
특별히 UI를 위해 데이터 형태를 바꿀 필요가 없으며, GPT 프롬프트 수정으로 새로운 정보(예: 할인율, 해시태그)를 추가하게 되면 프론트엔드 개발자에게 "새로운 필드명(Key)"만 전달해 주면 됩니다.

---

## 📱 프론트엔드(Flutter) 구현 가이드

프론트엔드에서는 다음 4단계를 거쳐 UI를 렌더링합니다.

### 1. 필드명 한글 번역 매핑 테이블 생성
서버에서 내려오는 영문 Key를 사용자에게 보여줄 예쁜 한글 라벨로 변환하는 Map을 만듭니다.

```dart
final Map<String, String> fieldLabels = {
  'title': '제목',
  'expires_at': '만료일',
  'start_at': '시작일',
  'name': '상호명',
  'address': '주소',
  'region': '지역',
  'product_name': '상품명',
  'price_amount': '가격',
  'memo': '메모',
  'original_price': '정가',
  'discount_rate': '할인율',
  'category': '카테고리',
  'rating': '평점',
  // 백엔드에서 새 필드가 추가되면 여기에 한 줄만 추가!
};
```

### 2. 카드 상단: 핵심 필드 (고정 배치)
각 분류 타입(`SCHEDULE`, `PLACE`, `WISHLIST`, `MEMO`)별로 가장 중요한 1~2개 필드만 추출해서 눈에 띄게 배치합니다.

- **SCHEDULE**: `fields['title']`, `fields['expires_at']`
- **PLACE**: `fields['name']`, `fields['address']`
- **WISHLIST**: `fields['product_name']`, `fields['price_amount']`

### 3. 카드 하단: 나머지 필드 (동적 렌더링)
핵심 필드를 제외한 **모든 나머지 데이터**를 반복문으로 돌면서 "라벨: 값" 형태로 자동 렌더링합니다.

```dart
// 동적 렌더링 로직 (수도코드)
Column(
  children: fields.entries.map((entry) {
    // 1. 이미 상단에 크게 그린 핵심 필드거나, 복수 항목 리스트(items)면 무시
    if (['name', 'address', 'items'].contains(entry.key)) return SizedBox(); 
    
    // 2. 값이 비어있으면 무시
    if (entry.value == null || entry.value == '') return SizedBox();

    // 3. 한글 매핑 찾기 (없으면 영어 Key 그대로 노출)
    String labelName = fieldLabels[entry.key] ?? entry.key;

    // 4. UI 렌더링
    return Row(
      children: [
        Text(labelName, style: TextStyle(color: Colors.grey)), // 예: "평점"
        SizedBox(width: 10),
        Text(entry.value.toString()),                          // 예: "4.5"
      ],
    );
  }).toList(),
)
```

### 4. 복수 항목 (items) 처리
맛집 리스트나 쇼핑 장바구니처럼 텍스트에 여러 항목이 포함된 경우, 백엔드는 `{"fields": {"items": [...]}}` 형태로 배열을 내려줍니다.
이 경우 Flutter의 **PageView** 위젯 등을 사용하여 사용자가 카드를 좌우로 스와이프하며 볼 수 있게 구현합니다.

```dart
if (fields.containsKey('items')) {
   return PageView.builder(
     itemCount: fields['items'].length,
     itemBuilder: (context, index) {
       // items 안의 개별 객체를 바탕으로 2번, 3번 로직을 적용해 카드 렌더링
       return buildCard(fields['items'][index]);
     }
   );
}
```

---

이렇게 구현하면 백엔드에서 프롬프트를 고쳐서 "해시태그"나 "전화번호" 같은 필드를 마음대로 추가해도, 앱을 다시 빌드하거나 코드를 고칠 필요 없이 알아서 카드 하단에 줄이 하나 추가되면서 렌더링됩니다! 🚀
