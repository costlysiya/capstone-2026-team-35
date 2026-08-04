from openai import OpenAI, APIError, APITimeoutError, RateLimitError
from app.config import OPENAI_MODEL, LLM_TEMPERATURE
import json
import logging
from tenacity import retry, retry_if_exception_type, wait_exponential, stop_after_attempt, before_sleep_log, RetryError

logger = logging.getLogger(__name__)
client = OpenAI()

@retry(
    retry=retry_if_exception_type((APITimeoutError, APIError, RateLimitError, json.JSONDecodeError)),
    wait=wait_exponential(multiplier=1, min=2, max=10),
    stop=stop_after_attempt(3),
    before_sleep=before_sleep_log(logger, logging.WARNING)
)
def _do_call_llm(system_prompt: str, user_text: str) -> dict:
    response = client.chat.completions.create(
        model=OPENAI_MODEL,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_text}
        ],
        response_format={"type": "json_object"},
        temperature=LLM_TEMPERATURE,
        timeout=30
    )
    result = json.loads(response.choices[0].message.content)
    return result

def call_llm(system_prompt: str, user_text: str, max_retries: int = 3) -> dict:
    """
    LLM을 안전하게 호출하는 함수 (Tenacity 적용)
    - 실패 시 지수적 백오프(Exponential Backoff)로 최대 3번 재시도
    - 최종 실패 시 에러 딕셔너리 반환
    """
    try:
        return _do_call_llm(system_prompt, user_text)
    except RetryError as e:
        last_error = e.last_attempt.exception()
        logger.error(f"LLM 호출 최종 실패 (재시도 초과): {last_error}")
        return {
            "type": "MEMO",
            "confidence": 0.0,
            "fields": {},
            "missing_fields": ["LLM 호출 실패 - 수동 입력 필요"],
            "error": str(last_error)
        }
