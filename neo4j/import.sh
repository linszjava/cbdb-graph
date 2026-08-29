#!/bin/bash
# 批量导入 Neo4j 5.x（离线，需先停掉 Neo4j）
# 注意：Community Edition 只支持一个用户库，必须导入名为 neo4j 的库
set -euo pipefail
cd "$(dirname "$0")"
DBNAME="${1:-neo4j}"

neo4j-admin database import full "$DBNAME" \
  --nodes=csv/nodes_person.csv \
  --nodes=csv/nodes_addr.csv \
  --nodes=csv/nodes_office.csv \
  --nodes=csv/nodes_text.csv \
  --nodes=csv/nodes_entry.csv \
  --relationships=csv/rels_kin.csv \
  --relationships=csv/rels_assoc.csv \
  --relationships=csv/rels_addr.csv \
  --relationships=csv/rels_office.csv \
  --relationships=csv/rels_posted.csv \
  --relationships=csv/rels_text.csv \
  --relationships=csv/rels_entry.csv \
  --id-type=integer \
  --skip-bad-relationships=true \
  --skip-duplicate-nodes=true \
  --high-parallel-io=on \
  --overwrite-destination=true

echo "导入完成。启动 Neo4j 后执行： cypher-shell -f schema.cypher"
