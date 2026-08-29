#!/bin/bash
# 密码从 .env 读，不写死在脚本里
[ -f "$(dirname "$0")/../.env" ] && . "$(dirname "$0")/../.env"
[ -f "$(dirname "$0")/.env" ] && . "$(dirname "$0")/.env"
: "${NEO4J_PASSWORD:?请先在项目根目录创建 .env 并设置 NEO4J_PASSWORD（可参考 .env.example）}"
cd "$(dirname "$0")"
pkill -f "spring-boot:run" 2>/dev/null && echo "后端已停" || echo "后端未运行"
pkill -f "frontend.*vite" 2>/dev/null && echo "前端已停" || echo "前端未运行"
docker compose -p cbdb stop neo4j && echo "Neo4j 已停"
