from openai import OpenAI, APIError, APITimeoutError, RateLimitError
from app.config import OPENAI_MODEL, LLM_TEMPERATURE
import json
import time
import logging

logger = logging.getLogger(__name__)
client = OpenAI()

def call_llm(system_prompt: str, user_text: str, max_retries: int = 3) -> dict:
    """
    LLM을 안전하게 호출하는 함수
    - 실패 시 최대 3번 재시도
    - JSON 파싱 실패 시 기본값 반환
    """
    last_error = None
    
    for attempt in range(max_retries):
        try:
            response = client.chat.completions.create(
                model=OPENAI_MODEL,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_text}
                ],
                response_format={"type": "json_object"},
                temperature=LLM_TEMPERATURE,
                timeout=30  # 30초 타임아웃
            )
            
            result = json.loads(response.choices[0].message.content)
            logger.info(f"LLM 호출 성공 (시도 {attempt + 1})")
            return result
            
        except (APITimeoutError, APIError) as e:
            last_error = e
            wait_time = 2 ** attempt  # 1초, 2초, 4초 대기
            logger.warning(f"LLM 호출 실패 (시도 {attempt + 1}): {e}. {wait_time}초 후 재시도")
            time.sleep(wait_time)
            
        except RateLimitError as e:
            last_error = e
            logger.warning(f"API 호출 한도 초과. 10초 대기 후 재시도")
            time.sleep(10)
            
        except json.JSONDecodeError as e:
            last_error = e
            logger.error(f"JSON 파싱 실패: {e}")
            # JSON이 깨졌으면 재시도
            continue
    
    # 모든 재시도 실패
    logger.error(f"LLM 호출 최종 실패: {last_error}")
    return {
        "type": "MEMO",
        "confidence": 0.0,
        "fields": {},
        "missing_fields": ["LLM 호출 실패 - 수동 입력 필요"],
        "error": str(last_error)
    }
