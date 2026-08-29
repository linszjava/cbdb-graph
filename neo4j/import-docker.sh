#!/bin/bash
# CBDB 批量导入（Docker）
# 警告：--overwrite-destination 会清空 neo4j 库中的全部现有数据
set -euo pipefail
# 密码从 .env 读，不写死在脚本里
[ -f "$(dirname "$0")/../.env" ] && . "$(dirname "$0")/../.env"
[ -f "$(dirname "$0")/.env" ] && . "$(dirname "$0")/.env"
: "${NEO4J_PASSWORD:?请先在项目根目录创建 .env 并设置 NEO4J_PASSWORD（可参考 .env.example）}"
cd "$(dirname "$0")/.."
C=/var/lib/neo4j/import/cbdb
DC="docker compose -p cbdb"

echo "▸ 移除手工创建的容器（数据在 bind mount 里，不受影响）"
docker rm -f neo4j 2>/dev/null || true

echo "▸ 批量导入"
$DC run --rm neo4j neo4j-admin database import full neo4j \
  --nodes="$C/nodes_person.csv" \
  --nodes="$C/nodes_addr.csv" \
  --nodes="$C/nodes_office.csv" \
  --nodes="$C/nodes_text.csv" \
  --nodes="$C/nodes_entry.csv" \
  --nodes="$C/nodes_nianhao.csv" \
  --nodes="$C/nodes_cohort.csv" \
  --relationships="$C/rels_kin.csv" \
  --relationships="$C/rels_assoc.csv" \
  --relationships="$C/rels_addr.csv" \
  --relationships="$C/rels_office.csv" \
  --relationships="$C/rels_posted.csv" \
  --relationships="$C/rels_text.csv" \
  --relationships="$C/rels_entry.csv" \
  --relationships="$C/rels_cohort.csv" \
  --relationships="$C/rels_place_belongs.csv" \
  --id-type=integer \
  --skip-bad-relationships=true \
  --skip-duplicate-nodes=true \
  --high-parallel-io=on \
  --overwrite-destination=true

echo "▸ 启动 Neo4j（带 APOC + GDS）"
$DC up -d neo4j

echo "▸ 等待就绪"
for i in $(seq 1 60); do
  docker exec neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" 'RETURN 1' >/dev/null 2>&1 && break
  sleep 3
done

echo "▸ 建立约束与索引"
docker exec -i neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" < neo4j/schema.cypher

echo "▸ 节点统计"
docker exec neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
  'MATCH (n) RETURN labels(n)[0] AS type, count(*) AS cnt ORDER BY cnt DESC'
