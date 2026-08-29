# CBDB 图谱工作台

把中国历代人物传记资料库（CBDB）建成可交互的知识图谱。
入库规模：789,709 节点 / 2,541,114 关系。

十一个模块：检索、人物档案、关系网络、家族世系、宦游地图、关系路径、
网络分析、史料溯源、科举同年、群体网络、政区层级。

## 首次搭建

**仓库不含 CBDB 数据**（原始快照 571 MB，且属 CBDB 项目所有），需自行获取。

```bash
# 1. 配置
cp .env.example .env        # 填入 NEO4J_PASSWORD 与 NEO4J_HOME

# 2. 取数据：从 CBDB 官方下载 SQLite 快照，放进 latest/
#    https://huggingface.co/datasets/cbdb/cbdb-sqlite
mkdir -p latest && mv ~/Downloads/cbdb_*.sqlite3 latest/

# 3. 建库：导出 → 繁转简 → 套用勘误 → 导入 → GDS 预计算
./neo4j/rebuild.sh

# 4. 起服务
./start.sh
```

依赖：Docker、Java 21、Maven、Node 20+、pnpm、Python 3（`pip install zhconv`）。

- 前端 http://localhost:5173
- API  http://localhost:8080/api
- Neo4j Browser http://localhost:7474

## 数据管道

```
latest/*.sqlite3  →  export.sh             忠实转储，不做任何改动
                  →  simplify.py           繁体转简体，nameChnT 保留原繁体
                  →  apply_corrections.py  套用 corrections.tsv 中的勘误
                  →  import-docker.sh      批量导入，7.5 秒
```

**原始快照永不修改。** 勘误是管道里一个显式、可审计、可撤销的步骤——
删掉 `neo4j/corrections.tsv` 里的一行即可撤销该修正，季度更新后会自动重新套用。

重新导入全库：

```bash
./neo4j/rebuild.sh
```

## 数据存储与导出

Neo4j 的数据在 **`$NEO4J_HOME/neo4j-data`**（bind mount 到容器的 `/data`）：

```
neo4j-data/
├── databases/neo4j       图存储文件，723 MB
├── databases/system      系统库（用户、角色、数据库元信息）
├── transactions/         事务日志，514 MB（可安全清理，见下）
└── dbms/                 认证信息
```

导出用 `./neo4j/dump.sh`，四种方式：

| 命令 | 产出 | 用途 |
|---|---|---|
| `dump.sh full` | `cbdb-YYYYMMDD-HHMM.dump` 146 MB · 33 秒 | 二进制全量，备份与迁移首选。**需停机** |
| `dump.sh cypher` | Cypher 脚本 | 纯文本，含 DDL + 数据，跨版本可移植 |
| `dump.sh schema` | 约束 + 索引 | 只要结构 |
| `dump.sh csv` | 618 MB · 1 分钟 | 给 Excel / pandas / Gephi |

产出位置：`full` 在 `neo4j-export/`，其余（走 APOC）在 `neo4j-import/exports/`——
**APOC 的路径一律相对 import 目录解析**，写绝对路径会被拼到 import 下面去。

恢复（`neo4j-admin load` 只认 `neo4j.dump` 这个文件名，先改名）：

```bash
docker compose -p cbdb stop neo4j
cp $NEO4J_HOME/neo4j-export/cbdb-20260829-1448.dump \
   $NEO4J_HOME/neo4j-export/neo4j.dump
docker compose -p cbdb run --rm -v $NEO4J_HOME/neo4j-export:/dumps neo4j \
  neo4j-admin database load neo4j --from-path=/dumps --overwrite-destination=true
docker compose -p cbdb up -d neo4j
```

校验转储文件（`DZV1` 是 Neo4j 的容器头，跳过 4 字节才是 zstd 流）：

```bash
tail -c +5 cbdb-YYYYMMDD-HHMM.dump | zstd -t
```

## 数据质量审计

```bash
./neo4j/audit.sh
```

检出库中自相矛盾的记载（世代方向、生卒年、父子年差等五类规则），结果存档为
`neo4j/audit-YYYYMMDD.txt`。只读，不改数据。确认属实的错误请登记到 `corrections.tsv`。

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/search?q=苏轼` | 全文检索，简繁皆可 |
| GET | `/api/person/{id}` | 人物档案 |
| GET | `/api/ego/{id}?hops=1&relTypes=ASSOC` | ego 网络，硬截断 500 节点 |
| GET | `/api/path?from=3767&to=3257` | 两人间最短关系链 |

## 已知约束

- Neo4j Community 只允许一个用户库，导入目标必须叫 `neo4j`
- `docker compose` 须带 `-p cbdb`（目录名是中文，无法自动生成项目名）
- `neo4j-admin database import` 需停机且会覆盖目标库，不能用于增量更新
- **全库只存简体**，繁体不落库；需要原繁体时从 `latest/` 下的 SQLite 重新导出
- 检索不用全文索引（中文按单字切分会返回大量噪音），改用 TEXT 索引做精确/前缀/包含三级匹配
- **重导数据后必须重启后端**——Caffeine 缓存会保留旧结果（TTL 6 小时）
