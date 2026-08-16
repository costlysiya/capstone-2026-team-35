import requests
import json

url = 'http://44.195.33.82:8000/api/analyze/v2'
payload = {
    'ocr_text': '가족 여행 일정: 2023년 12월 24일부터 2023년 12월 26일까지 부산 해운대',
    'type': 'SCHEDULE',
    'masked_tokens': []
}

response = requests.post(url, json=payload)
print(json.dumps(response.json(), ensure_ascii=False, indent=2))
