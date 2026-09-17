import urllib.request
import json
from datetime import datetime

url = 'http://44.195.33.82:8000/api/analyze/v2'

# Text pretending to be sent today
ocr_text = f"[현재 날짜: 2024년 8월 13일] 내일 1시에 보자"
data = json.dumps({
    'ocr_text': ocr_text,
    'type': 'SCHEDULE',
    'masked_tokens': []
}).encode('utf-8')

req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
try:
    with urllib.request.urlopen(req) as response:
        print(json.dumps(json.loads(response.read().decode()), ensure_ascii=False, indent=2))
except Exception as e:
    print(f"Error: {e}")
