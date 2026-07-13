from openai import OpenAI
from dotenv import load_dotenv
import json

load_dotenv()
client = OpenAI()

# 이런 OCR 텍스트가 앱에서 날아온다고 가정
ocr_text = """
[기프티콘] 스타벅스 아메리카노 T
유효기간: 2026.08.15
교환처: 스타벅스 전 매장
바코드: {MASKED_CARD}
"""

response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[
        {
            "role": "system",
            "content": """당신은 스크린샷 OCR 텍스트를 분석하는 AI입니다.
아래 4가지 타입 중 하나로 분류하고, 핵심 필드를 추출하세요:
- SCHEDULE: 기프티콘, 구독, 일정 (expires_at, title 필수)
- PLACE: 맛집, 카페 (name 또는 region 필수)  
- WISHLIST: 쇼핑 (product_name, price_amount 필수)
- MEMO: 텍스트 정보 (body 필수)

반드시 JSON 형식으로만 응답하세요."""
        },
        {
            "role": "user",
            "content": ocr_text
        }
    ],
    response_format={"type": "json_object"}  # JSON 강제!
)

result = json.loads(response.choices[0].message.content)
print(json.dumps(result, ensure_ascii=False, indent=2))