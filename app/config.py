from dotenv import load_dotenv
import os

load_dotenv()

# OpenAI
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_MODEL = "gpt-4o-mini"  # 모델 바꿀 때 여기만 수정

# DB
DB_PATH = "soseng.db"

# LLM 설정
LLM_TEMPERATURE = 0.1  # 낮을수록 일관된 답변
LLM_MAX_TOKENS = 1000
