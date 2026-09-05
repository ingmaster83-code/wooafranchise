#!/usr/bin/env python3
"""
fetch_brand_stats.py - 브랜드별 가맹점 현황+매출(FftcBrandFrcsStatsService) 전량 수집
연도 기준 플랫 페이지네이션.

출력: _rawdata/brand_stats_raw.json
"""
import json, os, sys, time
import requests

sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "_rawdata", "brand_stats_raw.json")

SERVICE_KEY = os.environ.get("DATA_GO_KR_API_KEY") or "9490b1d34e92aa9e25b32a4cff1438fc7b9c71e5d332413916a391e867f61e86"
BASE = "https://apis.data.go.kr/1130000/FftcBrandFrcsStatsService/getBrandFrcsStats"
YEAR = os.environ.get("FRANCHISE_YEAR", "2024")
PAGE_SIZE = 1000


def fetch_page(page_no, attempt=1):
    params = {
        "serviceKey": SERVICE_KEY, "resultType": "json",
        "pageNo": page_no, "numOfRows": PAGE_SIZE, "yr": YEAR,
    }
    try:
        r = requests.get(BASE, params=params, timeout=20)
        r.raise_for_status()
        return r.json()
    except Exception as e:
        if attempt >= 5:
            raise
        print(f"  [재시도 {attempt}] page {page_no}: {e}")
        time.sleep(3)
        return fetch_page(page_no, attempt + 1)


def main():
    all_items = []
    page = 1
    total_count = None
    while True:
        data = fetch_page(page)
        if data.get("resultCode") != "00":
            print("응답 이상:", json.dumps(data, ensure_ascii=False)[:300])
            break
        if total_count is None:
            total_count = data.get("totalCount", 0)
            print(f"전체 통계 건수({YEAR}년): {total_count}")
        items = data.get("items") or []
        if not items:
            break
        all_items.extend(items)
        print(f"  page {page}: 누적 {len(all_items)} / {total_count}")
        if len(all_items) >= total_count:
            break
        page += 1
        if page > 50:
            print("안전장치: 50페이지 초과, 중단")
            break
        time.sleep(0.1)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(all_items, f, ensure_ascii=False)
    print(f"\n총 {len(all_items)}건 저장 -> {OUT}")


if __name__ == "__main__":
    main()
