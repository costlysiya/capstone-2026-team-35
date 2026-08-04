from datetime import datetime, timezone
import uuid

def format_ics_datetime(date_str: str, time_str: str = None) -> str:
    """YYYY-MM-DD 와 HH:MM 을 받아서 ICS 호환 문자열로 반환 (예: 20260815T143000 또는 20260815)"""
    if not date_str:
        return ""
    
    date_clean = date_str.replace("-", "")
    if time_str:
        time_clean = time_str.replace(":", "")
        # 초(SS)가 없을 경우 00 추가
        if len(time_clean) == 4:
            time_clean += "00"
        return f"{date_clean}T{time_clean}"
    return date_clean

def generate_ics(fields: dict) -> str:
    """
    SCHEDULE 타입의 fields 딕셔너리를 받아 표준 iCalendar (.ics) 문자열을 반환합니다.
    """
    title = fields.get("title", "일정/예약")
    start_at = fields.get("start_at")
    expires_at = fields.get("expires_at")
    start_time = fields.get("start_time")
    end_time = fields.get("end_time")
    
    # 시작일이 없으면 만료일을 시작일로 사용
    if not start_at and expires_at:
        start_at = expires_at
        
    # 만약 둘 다 없으면 오늘 날짜를 임시로 사용
    if not start_at:
        start_at = datetime.now().strftime("%Y-%m-%d")

    dtstart = format_ics_datetime(start_at, start_time)
    
    # 종료일이 없으면 시작일과 동일하게 처리 (혹은 1시간 뒤)
    if end_time and not expires_at:
        dtend = format_ics_datetime(start_at, end_time)
    elif expires_at:
        dtend = format_ics_datetime(expires_at, end_time)
    else:
        # 종료 시간도 없으면 그냥 Date event
        dtend = dtstart

    description = fields.get("description", "")
    location = fields.get("exchange_place", "")
    
    uid = str(uuid.uuid4())
    now_stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    # .ics 포맷 구성
    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Soseng App//EN",
        "CALSCALE:GREGORIAN",
        "BEGIN:VEVENT",
        f"UID:{uid}",
        f"DTSTAMP:{now_stamp}",
        f"SUMMARY:{title}",
    ]
    
    # 날짜(Date) 전용 이벤트인지, 시간(DateTime) 포함 이벤트인지에 따라 속성명 분기
    if "T" in dtstart:
        lines.append(f"DTSTART:{dtstart}")
    else:
        lines.append(f"DTSTART;VALUE=DATE:{dtstart}")
        
    if "T" in dtend:
        lines.append(f"DTEND:{dtend}")
    else:
        # iCal 스펙상 하루 종일(Date) 이벤트의 끝날짜는 다음 날이어야 하지만, 여기서는 단순히 기록
        lines.append(f"DTEND;VALUE=DATE:{dtend}")

    if location:
        lines.append(f"LOCATION:{location}")
        
    if description:
        # 줄바꿈 이스케이프
        desc_clean = description.replace("\n", "\\n")
        lines.append(f"DESCRIPTION:{desc_clean}")
        
    lines.extend([
        "END:VEVENT",
        "END:VCALENDAR"
    ])
    
    # CRLF로 조인하는 것이 ICS 표준 권장
    return "\r\n".join(lines)
