#!/usr/bin/env python3
"""套用 neo4j/corrections.tsv 中的勘误到导出的 CSV。

设计原则：原始快照 latest/*.sqlite3 永不修改。勘误是管道里一个显式、
可审计、可撤销的步骤 —— 删掉 corrections.tsv 里的一行即可撤销该修正。
在 simplify.py 之后运行（按 id 定位，与简繁无关）。
"""
import csv, sys
from pathlib import Path

def load_rules(path):
    kin, person = [], []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.startswith("#"): continue
            parts = line.split("\t")
            if len(parts) < 6 or parts[0] == "类型": continue
            kind, target, field, old, new, why = parts[:6]
            (kin if kind == "kincode" else person).append(
                {"target": target, "field": field, "old": old, "new": new, "why": why})
    return kin, person

def patch(path, id_col, rules, match_col=None):
    """rules 按 target 分组，match_col 为空时用 id_col 匹配。"""
    by_target = {}
    for r in rules:
        by_target.setdefault(r["target"], []).append(r)
    if not by_target: return 0

    with open(path, newline="", encoding="utf-8") as fh:
        rows = list(csv.reader(fh))
    header, data = rows[0], rows[1:]
    key_col = header.index(match_col or id_col)
    cols = {}
    for rs in by_target.values():
        for r in rs:
            if r["field"] not in cols:
                idx = [i for i, h in enumerate(header) if h.split(":")[0] == r["field"]]
                if not idx:
                    print(f"!! {path.name} 无字段 {r['field']}"); sys.exit(1)
                cols[r["field"]] = idx[0]

    n = 0
    for row in data:
        rs = by_target.get(row[key_col])
        if not rs: continue
        for r in rs:
            c = cols[r["field"]]
            if row[c] == r["old"]:
                row[c] = r["new"]; n += 1
            elif row[c] != r["new"]:
                print(f"!! {path.name} id={row[key_col]} {r['field']} 现值 {row[c]!r}"
                      f" 与勘误表原值 {r['old']!r} 不符，跳过（上游数据可能已变）")
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh, quoting=csv.QUOTE_MINIMAL)
        w.writerow(header); w.writerows(data)
    return n

def main(csvdir, rules_file):
    d = Path(csvdir)
    kin, person = load_rules(rules_file)
    total = 0
    total += patch(d / "rels_kin.csv", ":START_ID(Person)", kin, match_col="kinCode:int")
    total += patch(d / "nodes_person.csv", "personId:ID(Person)", person)
    print(f"✓ 套用勘误 {total} 处（{len(kin)} 条关系码规则 · {len(person)} 条人物规则）")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "csv",
         sys.argv[2] if len(sys.argv) > 2 else "corrections.tsv")
