import threading
import logging

logger = logging.getLogger(__name__)

# 동시 LLM 호출 최대 수 (동시에 3개까지만 허용)
MAX_CONCURRENT_LLM = 3

# threading 기반 세마포어 (sync 엔드포인트용)
_llm_semaphore = threading.Semaphore(MAX_CONCURRENT_LLM)


def call_llm_with_limit(llm_func, *args, **kwargs):
    """
    세마포어로 동시 LLM 호출 수를 제한.
    MAX_CONCURRENT_LLM개 초과 시 대기열에 들어감.
    """
    logger.info(f"[concurrency] LLM 호출 대기 중... (현재 가용: {_llm_semaphore._value})")
    with _llm_semaphore:
        logger.info(f"[concurrency] LLM 호출 시작 (남은 슬롯: {_llm_semaphore._value})")
        return llm_func(*args, **kwargs)
