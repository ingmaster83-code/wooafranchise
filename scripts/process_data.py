#!/usr/bin/env python3
"""
process_data.py - 브랜드 목록 + 매출통계 + 부담금 + 가맹본부상세를 병합해 Jekyll 페이지용
JSON으로 가공한다.

입력:
  _rawdata/brand_list_raw.json  - 전국 11,683개 브랜드 목록 (마스터)
  _rawdata/brand_stats_raw.json - 가맹점현황+매출 (corpNm+brandNm으로 조인)
  _rawdata/brand_fee.json       - {brandMnno: {...}} 부담금, 점진적으로 채워짐
  _rawdata/hq_detail.json       - {jnghdqrtrsMnno: {...}} 가맹본부 상세, 점진적으로 채워짐
출력:
  _rawdata/industry_{대분류}.json
  search_index.json
  _rawdata/stats.json
"""
import json, re, hashlib, sys
from pathlib import Path
from collections import defaultdict, Counter

sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).parent.parent
RAW_LIST = ROOT / "_rawdata" / "brand_list_raw.json"
RAW_STATS = ROOT / "_rawdata" / "brand_stats_raw.json"
RAW_FEE = ROOT / "_rawdata" / "brand_fee.json"
RAW_HQ = ROOT / "_rawdata" / "hq_detail.json"
RAWDATA_DIR = ROOT / "_rawdata"
SEARCH_INDEX_OUT = ROOT / "search_index.json"
STATS_OUT = ROOT / "_rawdata" / "stats.json"


def load(path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def slugify(text: str, extra: str) -> str:
    slug = re.sub(r"[^\w가-힣\s-]", "", text or "").strip()
    slug = re.sub(r"\s+", "-", slug)
    slug = re.sub(r"-+", "-", slug)
    h = hashlib.md5((text + "|" + extra).encode("utf-8")).hexdigest()[:6]
    return f"{slug}-{h}" if slug else h


def clean_category(text):
    """업종중분류명에 파일경로를 깨뜨리는 '/' 가 섞여있는 경우가 있어(예: '의류 / 패션')
    URL/디렉토리 이름으로도 그대로 쓰이므로 안전한 구분자로 치환."""
    if not text:
        return text
    return re.sub(r"\s*/\s*", "·", text).strip()


def fmt_amt(v):
    """단위:천원 문자열/숫자를 만원 단위 표기로 변환. 범위값("5200~5800")도 처리."""
    if v is None or v == "":
        return None
    s = str(v)
    try:
        if "~" in s:
            a, b = s.split("~")
            return f"{int(a) // 10}~{int(b) // 10}만원"
        return f"{int(float(s)) // 10}만원"
    except Exception:
        return s


def main():
    brands = load(RAW_LIST, [])
    stats_raw = load(RAW_STATS, [])
    fee_map = load(RAW_FEE, {})
    hq_map = load(RAW_HQ, {})

    stats_by_key = {}
    for s in stats_raw:
        stats_by_key[(s.get("corpNm"), s.get("brandNm"))] = s

    print(f"브랜드 {len(brands)}건, 매출통계 {len(stats_raw)}건, 부담금 확보 {len(fee_map)}건, 본부상세 확보 {len(hq_map)}건")

    items = []
    seen_slugs = Counter()
    skipped = 0
    for b in brands:
        brand_mnno = b.get("brandMnno")
        hq_mnno = b.get("jnghdqrtrsMnno")
        brand_nm = (b.get("brandNm") or "").strip()
        corp_nm = (b.get("corpNm") or "").strip()
        lclas = clean_category(b.get("indutyLclasNm"))
        mlsfc = clean_category(b.get("indutyMlsfcNm"))
        if not brand_mnno or not brand_nm or not lclas:
            skipped += 1
            continue

        slug = slugify(brand_nm, brand_mnno)
        seen_slugs[slug] += 1
        if seen_slugs[slug] > 1:
            slug = f"{slug}-{seen_slugs[slug]}"

        stat = stats_by_key.get((corp_nm, brand_nm)) or {}
        fee = fee_map.get(brand_mnno) or {}
        hq = hq_map.get(hq_mnno) or {}

        items.append({
            "brandMnno": brand_mnno,
            "brandNm": brand_nm,
            "corpNm": corp_nm,
            "lclas": lclas,
            "mlsfc": mlsfc,
            "majrGds": b.get("majrGdsNm") or "",
            "bizStrtDate": b.get("jngBizStrtDate") or "",
            "rprsvNm": b.get("jnghdqrtrsRprsvNm") or "",
            "slug": slug,
            "hasFee": bool(fee),
            "hasHq": bool(hq),
            # 매출/가맹점현황
            "frcsCnt": stat.get("frcsCnt"),
            "newFrcsCnt": stat.get("newFrcsRgsCnt"),
            "ctrtEndCnt": stat.get("ctrtEndCnt"),
            "avrgSls": fmt_amt(stat.get("avrgSlsAmt")),
            "arUnitAvrgSls": fmt_amt(stat.get("arUnitAvrgSlsAmt")),
            # 부담금
            "jngAmt": fmt_amt(fee.get("jngAmtScopeVal")),
            "eduAmt": fmt_amt(fee.get("eduAmtScopeVal")),
            "assrncAmt": fmt_amt(fee.get("assrncAmtScopeVal")),
            "etcAmt": fmt_amt(fee.get("etcAmtScopeVal")),
            "smtnAmt": fmt_amt(fee.get("smtnAmtScopeVal")),
            # 가맹본부
            "hqNm": hq.get("jnghdqrtrsConmNm") or corp_nm,
            "hqTel": hq.get("jnghdqrtrsRprsTelno") or "",
            "hqAddr": hq.get("lctnAddr") or "",
            "hqAddrDetail": hq.get("lctnDaddr") or "",
            "brandCnt": hq.get("brandCnt"),
            "affltsCnt": hq.get("affltsCnt"),
            "entScale": hq.get("entScaleNm") or "",
            "hmpgUrl": hq.get("hmpgUrladr") or "",
            "areaNm": hq.get("areaNm") or "",
        })

    print(f"제외: {skipped}건")

    by_lclas = defaultdict(list)
    for it in items:
        by_lclas[it["lclas"]].append(it)

    RAWDATA_DIR.mkdir(parents=True, exist_ok=True)
    for lclas, group in by_lclas.items():
        out = RAWDATA_DIR / f"industry_{lclas}.json"
        out.write_text(json.dumps(group, ensure_ascii=False), encoding="utf-8")
        size_mb = out.stat().st_size / 1024 / 1024
        print(f"  {lclas}: {len(group)}건 -> {out.name} ({size_mb:.1f}MB)")

    index = [
        {"n": it["brandNm"], "c": it["corpNm"], "l": it["lclas"], "m": it["mlsfc"], "s": it["slug"], "f": it["hasFee"]}
        for it in items
    ]
    SEARCH_INDEX_OUT.write_text(json.dumps(index, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    size_mb = SEARCH_INDEX_OUT.stat().st_size / 1024 / 1024
    print(f"\n검색 인덱스 {len(index)}개 저장 -> {SEARCH_INDEX_OUT} ({size_mb:.1f}MB)")

    fee_filled = sum(1 for it in items if it["hasFee"])
    hq_filled = sum(1 for it in items if it["hasHq"])
    stats_out = {
        "total": len(items),
        "feeFilled": fee_filled, "feePct": round(fee_filled * 100 / max(len(items), 1), 1),
        "hqFilled": hq_filled, "hqPct": round(hq_filled * 100 / max(len(items), 1), 1),
    }
    STATS_OUT.write_text(json.dumps(stats_out, ensure_ascii=False), encoding="utf-8")
    print(f"부담금 진행률: {fee_filled}/{len(items)} ({stats_out['feePct']}%)")
    print(f"본부상세 진행률: {hq_filled}/{len(items)} ({stats_out['hqPct']}%)")


if __name__ == "__main__":
    main()
