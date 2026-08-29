#!/bin/bash
# 把 dump 恢复到另一台 Neo4j（Docker 版）。
#
#   ./neo4j/restore.sh <dump文件> [数据目录] [端口前缀]
#   例：./neo4j/restore.sh cbdb-20260829-1448.dump ~/neo4j-new 7474
#
# 注意：
#   - 目标 Neo4j 版本必须 >= 源版本（本项目源为 2026.07.1），低版本装不进去
#   - Community 版只允许一个用户库，库名必须是 neo4j
#   - neo4j-admin load 只认 <库名>.dump 这个文件名，脚本会自动改名
#   - GDS 算出的 community / betweenness / pagerank 是普通节点属性，随 dump 一起走，
#     恢复后无需重算；但要再跑算法或用 apoc.*，目标机仍需装插件
set -euo pipefail
# 密码从 .env 读，不写死在脚本里
[ -f "$(dirname "$0")/../.env" ] && . "$(dirname "$0")/../.env"
[ -f "$(dirname "$0")/.env" ] && . "$(dirname "$0")/.env"
: "${NEO4J_PASSWORD:?请先在项目根目录创建 .env 并设置 NEO4J_PASSWORD（可参考 .env.example）}"
DUMP="${1:?用法: $0 <dump文件> [数据目录] [端口]}"
DATA="${2:-$HOME/neo4j-restored}"
PORT="${3:-7474}"
BOLT=$((PORT + 213))          # 7474 → 7687
IMAGE=neo4j:2026.07.1
PASS="$NEO4J_PASSWORD"

[ -f "$DUMP" ] || { echo "找不到 $DUMP"; exit 1; }
mkdir -p "$DATA/data" "$DATA/dumps"
cp "$DUMP" "$DATA/dumps/neo4j.dump"        # load 只认这个文件名

echo "▸ 装载 dump 到 $DATA/data"
docker run --rm -v "$DATA/data:/data" -v "$DATA/dumps:/dumps" "$IMAGE" \
  neo4j-admin database load neo4j --from-path=/dumps --overwrite-destination=true 2>&1 \
  | grep -E "^Done:|Command Failed" || true

echo "▸ 启动实例（HTTP $PORT / Bolt $BOLT）"
docker rm -f neo4j-restored 2>/dev/null || true
docker run -d --name neo4j-restored \
  -p "$PORT:7474" -p "$BOLT:7687" \
  -v "$DATA/data:/data" \
  -e NEO4J_AUTH="neo4j/$PASS" \
  -e NEO4J_PLUGINS='["apoc","graph-data-science"]' \
  -e NEO4J_dbms_security_procedures_unrestricted='gds.*,apoc.*' \
  -e NEO4J_dbms_security_procedures_allowlist='gds.*,apoc.*' \
  -e NEO4J_server_memory_heap_max__size=4G \
  -e NEO4J_server_memory_pagecache_size=4G \
  "$IMAGE" > /dev/null

echo "▸ 等待就绪"
until docker exec neo4j-restored cypher-shell -u neo4j -p "$PASS" 'RETURN 1' >/dev/null 2>&1; do sleep 5; done

echo "▸ 核对"
docker exec neo4j-restored cypher-shell -u neo4j -p "$PASS" \
  'MATCH (n) RETURN count(n) AS 节点' 
docker exec neo4j-restored cypher-shell -u neo4j -p "$PASS" \
  'MATCH ()-[r]->() RETURN count(r) AS 关系'
echo
echo "完成 → http://localhost:$PORT  （bolt://localhost:$BOLT）"
