#!/bin/bash
# 一键启动 CBDB 图谱工作台
set -euo pipefail
# 密码从 .env 读，不写死在脚本里
[ -f "$(dirname "$0")/../.env" ] && . "$(dirname "$0")/../.env"
[ -f "$(dirname "$0")/.env" ] && . "$(dirname "$0")/.env"
: "${NEO4J_PASSWORD:?请先在项目根目录创建 .env 并设置 NEO4J_PASSWORD（可参考 .env.example）}"
cd "$(dirname "$0")"

echo "▸ Neo4j"
docker compose -p cbdb up -d neo4j
until docker exec neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" 'RETURN 1' >/dev/null 2>&1; do sleep 3; done
echo "  就绪 → http://localhost:7474"

echo "▸ 后端 API"
(cd backend && nohup mvn -q -B spring-boot:run > /tmp/cbdb-api.log 2>&1 &)
for i in $(seq 1 40); do
  curl -s -m 3 http://localhost:8080/api/health 2>/dev/null | grep -q ok && break
  sleep 3
done
echo "  就绪 → http://localhost:8080/api/health"

echo "▸ 前端"
(cd frontend && nohup pnpm dev > /tmp/cbdb-web.log 2>&1 &)
sleep 4
echo "  就绪 → http://localhost:5173"
echo
echo "日志：/tmp/cbdb-api.log · /tmp/cbdb-web.log"
echo "停止：./stop.sh"
