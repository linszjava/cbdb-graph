#!/bin/bash
# Neo4j 数据导出。四种方式，用途不同。
#
#   ./neo4j/dump.sh full     二进制全量转储（需停机，最快最完整，用于备份/迁移）
#   ./neo4j/dump.sh cypher   Cypher 脚本（schema + 数据，纯文本，跨版本可移植）
#   ./neo4j/dump.sh schema   只导结构（约束 + 索引）
#   ./neo4j/dump.sh csv      导成 CSV（节点、关系各一份）
#
# 产出位置：
#   full          → ${NEO4J_HOME}/neo4j-export/
#   其余（APOC）  → ${NEO4J_HOME}/neo4j-import/exports/
#   （APOC 的路径一律相对 import 目录解析，写绝对路径会被拼到 import 下面）
set -euo pipefail
# 密码从 .env 读，不写死在脚本里
[ -f "$(dirname "$0")/../.env" ] && . "$(dirname "$0")/../.env"
[ -f "$(dirname "$0")/.env" ] && . "$(dirname "$0")/.env"
: "${NEO4J_PASSWORD:?请先在项目根目录创建 .env 并设置 NEO4J_PASSWORD（可参考 .env.example）}"
cd "$(dirname "$0")/.."
MODE="${1:-schema}"
STAMP=$(date +%Y%m%d-%H%M)
CY="docker exec neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD""
HOST_APOC=${NEO4J_HOME}/neo4j-import/exports
HOST_DUMP=${NEO4J_HOME}/neo4j-export
mkdir -p "$HOST_APOC" "$HOST_DUMP"

case "$MODE" in
  full)
    echo "▸ 停止数据库（neo4j-admin dump 要求离线）"
    docker compose -p cbdb stop neo4j
    echo "▸ 转储"
    docker compose -p cbdb run --rm -v "$HOST_DUMP:/dumps" neo4j \
      neo4j-admin database dump neo4j --to-path=/dumps --overwrite-destination=true
    # neo4j-admin 固定输出 neo4j.dump，改名加时间戳，免得每次备份覆盖上一次
    mv "$HOST_DUMP/neo4j.dump" "$HOST_DUMP/cbdb-$STAMP.dump"
    echo "▸ 重启"
    docker compose -p cbdb up -d neo4j
    until docker exec neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" 'RETURN 1' >/dev/null 2>&1; do sleep 3; done
    ls -lht "$HOST_DUMP"/*.dump
    echo
    echo "恢复（先把要恢复的那份改名回 neo4j.dump）："
    echo "  docker compose -p cbdb stop neo4j"
    echo "  cp $HOST_DUMP/cbdb-$STAMP.dump $HOST_DUMP/neo4j.dump"
    echo "  docker compose -p cbdb run --rm -v $HOST_DUMP:/dumps neo4j \\"
    echo "    neo4j-admin database load neo4j --from-path=/dumps --overwrite-destination=true"
    echo "  docker compose -p cbdb up -d neo4j"
    ;;

  cypher)
    OUT="exports/cbdb-$STAMP.cypher"
    echo "▸ 导出 Cypher（数据量大，预计数分钟且文件可达数 GB）"
    $CY "CALL apoc.export.cypher.all('$OUT', {
           format: 'cypher-shell',
           useOptimizations: {type: 'UNWIND_BATCH', unwindBatchSize: 1000}
         }) YIELD file, nodes, relationships, properties
         RETURN file, nodes, relationships, properties"
    ls -lh "$HOST_APOC"/$(basename "$OUT")
    echo "导入：cat 该文件 | docker exec -i neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD""
    ;;

  schema)
    OUT="exports/cbdb-schema-$STAMP.cypher"
    $CY "CALL apoc.export.cypher.schema('$OUT', {format:'plain'}) YIELD file RETURN file"
    echo "── 结构 ──"
    cat "$HOST_APOC/$(basename "$OUT")"
    ;;

  csv)
    OUT="exports/cbdb-$STAMP.csv"
    echo "▸ 导出 CSV（单文件，节点与关系混排）"
    $CY "CALL apoc.export.csv.all('$OUT', {}) YIELD file, nodes, relationships
         RETURN file, nodes, relationships"
    ls -lh "$HOST_APOC/$(basename "$OUT")"
    ;;

  *) echo "用法：$0 {full|cypher|schema|csv}"; exit 1 ;;
esac
