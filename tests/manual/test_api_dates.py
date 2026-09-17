import urllib.request
import json

url = 'http://44.195.33.82:8000/api/analyze/v2'
data = json.dumps({
    'ocr_text': '여행: 2023년 12월 24일, 2023년 12월 26일',
    'type': 'SCHEDULE',
    'masked_tokens': []
}).encode('utf-8')

req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
try:
    with urllib.request.urlopen(req) as response:
        print(json.dumps(json.loads(response.read().decode()), ensure_ascii=False, indent=2))
except Exception as e:
    print(f"Error: {e}")
