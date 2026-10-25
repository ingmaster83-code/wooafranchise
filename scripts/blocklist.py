# -*- coding: utf-8 -*-
"""삭제 요청된 가맹본부/브랜드 차단 목록 로더. fetch_*.py / process_data.py 에서 사용."""
import json
from pathlib import Path
_B = json.loads((Path(__file__).parent / "blocklist.json").read_text(encoding="utf-8"))
HQ, BRNO, BRAND = set(_B["hq"]), set(_B["brno"]), set(_B["brand"])
STATS = {tuple(x) for x in _B.get("stats", [])}   # (corpNm, brandNm) 정확 일치

def blocked_brand(b):
    """brand_list_raw 항목 하나가 차단 대상인지"""
    return b.get("brandMnno") in BRAND or b.get("jnghdqrtrsMnno") in HQ or b.get("brno") in BRNO
