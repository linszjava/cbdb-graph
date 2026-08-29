#!/usr/bin/env python3
"""繁体 → 简体：转换导出 CSV 中的所有中文文本列。

export.sh 保持对 CBDB 原始数据的忠实转储；简繁转换是这里一个显式、可重跑的独立步骤。
库中只保留简体。原繁体不落库 —— 需要时从 latest/ 下的原始 SQLite 重新导出即可。
"""
import csv, sys, zhconv
from pathlib import Path

# 文件 → 需要转换的列
TARGETS = {
    "nodes_person.csv": ["nameChn", "surnameChn", "mingziChn", "dynastyChn",
                         "altNames", "altLabels", "statuses", "choronym", "notes"],
    "nodes_addr.csv":   ["nameChn"],
    "nodes_office.csv": ["officeChn"],
    "nodes_text.csv":   ["titleChn"],
    "nodes_entry.csv":  ["descChn"],
    "nodes_nianhao.csv":["nameChn", "dynastyChn"],
    "nodes_cohort.csv": ["entryChn"],
    "rels_cohort.csv":  ["rank"],
    "rels_kin.csv":     ["relChn", "pages"],
    "rels_assoc.csv":   ["relChn", "textTitle", "pages"],
    "rels_addr.csv":    ["typeChn", "pages"],
    "rels_office.csv":  ["pages"],
    "rels_text.csv":    ["roleChn"],
    "rels_entry.csv":   ["rank"],
    # rels_office.csv / rels_posted.csv 无中文列
}

_cache = {}
def conv(s):
    if not s:
        return s
    v = _cache.get(s)
    if v is None:
        v = zhconv.convert(s, "zh-cn")
        _cache[s] = v
    return v

def main(csvdir):
    d = Path(csvdir)
    for fname, cols in TARGETS.items():
        p = d / fname
        if not p.exists():
            print(f"跳过（不存在）: {fname}"); continue

        with p.open(newline="", encoding="utf-8") as fh:
            rows = list(csv.reader(fh))
        header, data = rows[0], rows[1:]

        # 表头可能带 neo4j 类型后缀（altNames:string[]），按冒号前的名字匹配
        base = [h.split(":")[0] for h in header]
        idx = {c: base.index(c) for c in cols if c in base}
        missing = [c for c in cols if c not in base]
        if missing:
            print(f"!! {fname} 缺少列: {missing}"); sys.exit(1)

        changed = 0
        out = []
        for row in data:
            for c, i in idx.items():
                j = i
                orig = row[j]
                new = conv(orig)
                if new != orig:
                    changed += 1
                row[j] = new
            out.append(row)

        with p.open("w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh, quoting=csv.QUOTE_MINIMAL)
            w.writerow(header)
            w.writerows(out)
        print(f"✓ {fname:22s} {len(out):>7} 行，转换 {changed:>7} 个字段值")

    print(f"\n转换缓存去重后 {len(_cache)} 个不同字符串")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "csv")
