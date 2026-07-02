from fastapi import APIRouter, HTTPException
from openai import OpenAI
from app.config import OPENAI_MODEL, LLM_TEMPERATURE
from app.schemas import AnalyzeRequest, AnalyzeResponse
from app.prompts import get_system_prompt
from app.validator import validate_result
from app.database import save_result
import json

router = APIRouter(prefix="/api", tags=["분석"])
client = OpenAI()

@router.post("/analyze", response_model=AnalyzeResponse)
def analyze_screenshot(request: AnalyzeRequest):
    """OCR 텍스트를 받아 분류 + 구조화"""
    try:
        response = client.chat.completions.create(
            model=OPENAI_MODEL,
            messages=[
                {"role": "system", "content": get_system_prompt()},
                {"role": "user", "content": request.ocr_text}
            ],
            response_format={"type": "json_object"},
            temperature=LLM_TEMPERATURE
        )

        result = json.loads(response.choices[0].message.content)
        result = validate_result(result)

        # DB 저장
        row_id = save_result(
            type=result["type"],
            confidence=result.get("confidence", 0),
            fields=json.dumps(result.get("fields", {}), ensure_ascii=False)
        )

        return AnalyzeResponse(
            id=row_id,
            type=result["type"],
            confidence=result.get("confidence", 0),
            fields=result.get("fields", {}),
            missing_fields=result.get("missing_fields", []),
            status=result.get("status", "DRAFT")
        )

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"분석 실패: {str(e)}")