from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()  # .env 파일에서 API 키 읽어오기
client = OpenAI()  # 자동으로 OPENAI_API_KEY 환경변수를 사용

# ChatGPT에게 물어보기
response = client.chat.completions.create(
    model="gpt-4o-mini",        # 저렴하고 빠른 모델 (테스트용)
    messages=[
        {"role": "system", "content": "너는 한국어로 답하는 도우미야."},
        {"role": "user", "content": "스크린샷에서 기프티콘 유효기간을 추출하려면 어떻게 해?"}
    ]
)

# 답변 출력
print(response.choices[0].message.content)