#!/bin/bash
# 跑一遍数据质量审计并存档结果
set -euo pipefail
# 密码从 .env 读，不写死在脚本里
[ -f "$(dirname "$0")/../.env" ] && . "$(dirname "$0")/../.env"
[ -f "$(dirname "$0")/.env" ] && . "$(dirname "$0")/.env"
: "${NEO4J_PASSWORD:?请先在项目根目录创建 .env 并设置 NEO4J_PASSWORD（可参考 .env.example）}"
cd "$(dirname "$0")/.."
OUT="neo4j/audit-$(date +%Y%m%d).txt"
docker exec -i neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" --format plain < neo4j/audit.cypher > "$OUT"
echo "审计结果 → $OUT"
grep -c '^"规则' "$OUT" 2>/dev/null || true
