from datetime import datetime, timezone
import uuid

def format_ics_datetime(date_str: str, time_str: str = None) -> str:
    """YYYY-MM-DD 와 HH:MM 을 받아서 ICS 호환 문자열로 반환 (예: 20260815T143000 또는 20260815)"""
    if not date_str:
        return ""
    
    date_clean = date_str.replace("-", "")
    if time_str:
        time_clean = time_str.replace(":", "")
        # Append 00 for seconds if missing
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
    
    # Fallback start_at to expires_at
    if not start_at and expires_at:
        start_at = expires_at
        
    # Fallback to current date if both are missing
    if not start_at:
        start_at = datetime.now().strftime("%Y-%m-%d")

    dtstart = format_ics_datetime(start_at, start_time)
    
    # Default end_at to start_at + 1 hour
    if end_time and not expires_at:
        dtend = format_ics_datetime(start_at, end_time)
    elif expires_at:
        dtend = format_ics_datetime(expires_at, end_time)
    else:
        # Treat as all-day Date event if end_time is missing
        dtend = dtstart

    description = fields.get("description", "")
    location = fields.get("exchange_place", "")
    
    uid = str(uuid.uuid4())
    now_stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    # Generate .ics format
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
    
    # DTSTART/DTEND property names depend on whether it's an all-day event
    if "T" in dtstart:
        lines.append(f"DTSTART:{dtstart}")
    else:
        lines.append(f"DTSTART;VALUE=DATE:{dtstart}")
        
    if "T" in dtend:
        lines.append(f"DTEND:{dtend}")
    else:
        # Add 1 day to end_date for all-day events (iCal standard)
        lines.append(f"DTEND;VALUE=DATE:{dtend}")

    if location:
        lines.append(f"LOCATION:{location}")
        
    if description:
        # Escape newlines
        desc_clean = description.replace("\n", "\\n")
        lines.append(f"DESCRIPTION:{desc_clean}")
        
    lines.extend([
        "END:VEVENT",
        "END:VCALENDAR"
    ])
    
    # Join with CRLF (iCal standard)
    return "\r\n".join(lines)
