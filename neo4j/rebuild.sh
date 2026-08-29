#!/bin/bash
# 从 SQLite 原始快照重建整个图库
set -euo pipefail
# 密码从 .env 读，不写死在脚本里
[ -f "$(dirname "$0")/../.env" ] && . "$(dirname "$0")/../.env"
[ -f "$(dirname "$0")/.env" ] && . "$(dirname "$0")/.env"
: "${NEO4J_PASSWORD:?请先在项目根目录创建 .env 并设置 NEO4J_PASSWORD（可参考 .env.example）}"
cd "$(dirname "$0")/.."

echo "▸ 1/6 导出"           ; ./neo4j/export.sh > /dev/null
echo "▸ 2/6 繁转简"         ; python3 neo4j/simplify.py neo4j/csv > /dev/null
echo "▸ 3/6 套用勘误"       ; python3 neo4j/apply_corrections.py neo4j/csv neo4j/corrections.tsv
echo "▸ 4/6 暂存到 import 目录"
cp neo4j/csv/*.csv ${NEO4J_HOME}/neo4j-import/cbdb/
echo "▸ 5/6 导入"           ; ./neo4j/import-docker.sh 2>&1 | grep -E "Imported|nodes$|relationships$|properties$|type, cnt|^\"" 

# import 会清空数据库，GDS 结果必须重算
echo "▸ 6/6 GDS 预计算（分朝代社群与中心性，约 40 秒）"
docker exec -i neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" --format plain < neo4j/gds.cypher > /dev/null
docker exec neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
  'MATCH (p:Person) WHERE p.community IS NOT NULL
   RETURN count(*) AS 已标注社群人物, count(DISTINCT p.community) AS 社群数' 

if pgrep -f "spring-boot:run" > /dev/null; then
  echo; echo "▸ 重启后端以清空 Caffeine 缓存"
  pkill -f "spring-boot:run" || true; sleep 2
  (cd backend && nohup mvn -q -B spring-boot:run > /tmp/cbdb-api.log 2>&1 &)
  for i in $(seq 1 40); do
    curl -s -m 3 http://localhost:8080/api/health 2>/dev/null | grep -q ok && break
    sleep 3
  done
  echo "  后端已重启"
fi
