#!/usr/bin/env python3
"""
fetch_brand_fee.py - 브랜드별 부담금정보(가맹비/교육비/보증금/기타/합계)를 브랜드관리번호 1개당
1콜로 수집한다. 개발계정 트래픽이 100,000/일로 넉넉해서 전체를 한 번에 시도한다.

사용법: python scripts/fetch_brand_fee.py [--limit N]
"""
import json, os, sys, time, argparse
import requests

sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_LIST = os.path.join(ROOT, "_rawdata", "brand_list_raw.json")
CACHE = os.path.join(ROOT, "_rawdata", "brand_fee.json")

SERVICE_KEY = os.environ.get("DATA_GO_KR_API_KEY") or "9490b1d34e92aa9e25b32a4cff1438fc7b9c71e5d332413916a391e867f61e86"
BASE = "https://apis.data.go.kr/1130000/FftcBrandFrcsAlotmInfo2_Service/getbrandFrcsbzmnAlotminfo"
YEAR = os.environ.get("FRANCHISE_YEAR", "2024")
DEFAULT_LIMIT = 12000


def fetch_one(brand_mnno, attempt=1):
    params = {
        "serviceKey": SERVICE_KEY, "resultType": "json",
        "pageNo": 1, "numOfRows": 5, "jngBizCrtraYr": YEAR, "brandMnno": brand_mnno,
    }
    try:
        r = requests.get(BASE, params=params, timeout=15)
        r.raise_for_status()
        data = r.json()
        items = data.get("items") or []
        return items[0] if items else {}
    except Exception as e:
        if attempt >= 3:
            print(f"  실패 {brand_mnno}: {e}")
            return None
        time.sleep(2)
        return fetch_one(brand_mnno, attempt + 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=DEFAULT_LIMIT)
    args = ap.parse_args()

    brands = json.loads(open(RAW_LIST, encoding="utf-8").read())
    all_codes = [b["brandMnno"] for b in brands if b.get("brandMnno")]

    cache = {}
    if os.path.exists(CACHE):
        cache = json.loads(open(CACHE, encoding="utf-8").read())

    remaining = [c for c in all_codes if c not in cache]
    print(f"전체 {len(all_codes)}개 / 확보 {len(cache)}개 / 남음 {len(remaining)}개")
    if not remaining:
        print("완료!")
        return

    todo = remaining[: args.limit]
    print(f"이번 실행에서 {len(todo)}개 수집 시도...")

    ok, empty, fail = 0, 0, 0
    for i, code in enumerate(todo, 1):
        item = fetch_one(code)
        if item is None:
            fail += 1
        elif not item:
            cache[code] = {}
            empty += 1
        else:
            cache[code] = item
            ok += 1
        if i % 500 == 0:
            print(f"  진행 {i}/{len(todo)} (성공 {ok}, 데이터없음 {empty}, 실패 {fail})")
            with open(CACHE, "w", encoding="utf-8") as f:
                json.dump(cache, f, ensure_ascii=False)
        time.sleep(0.03)

    with open(CACHE, "w", encoding="utf-8") as f:
        json.dump(cache, f, ensure_ascii=False)
    print(f"\n완료: 성공 {ok} / 데이터없음 {empty} / 실패 {fail}")
    print(f"누적 확보: {len(cache)} / {len(all_codes)} ({len(cache)*100//len(all_codes)}%)")


if __name__ == "__main__":
    main()
