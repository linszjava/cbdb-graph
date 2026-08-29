// ===== 1. 人物 ego 网络（后端主力查询，:params {name:'朱熹', hops:1}）=====
MATCH (p:Person {nameChn:$name})
CALL apoc.path.subgraphAll(p, {maxLevel:$hops, relationshipFilter:'KIN|ASSOC'})
YIELD nodes, relationships
RETURN nodes, relationships;

// 不依赖 APOC 的等价写法
MATCH (p:Person {nameChn:'朱熹'})-[r:ASSOC]-(q:Person)
RETURN p, r, q LIMIT 300;

// ===== 2. 两人之间的关系路径（史学上最有说服力的一类结果）=====
MATCH (a:Person {nameChn:'朱熹'}), (b:Person {nameChn:'辛棄疾'})
MATCH path = shortestPath((a)-[:ASSOC|KIN*..6]-(b))
RETURN [n IN nodes(path) | n.nameChn] AS 人物链,
       [r IN relationships(path) | r.relChn] AS 关系链;

// ===== 3. 师承谱系（朱熹门下三代）=====
MATCH path = (master:Person {nameChn:'朱熹'})<-[:ASSOC*1..3 {relChn:'為Y之學生'}]-(disciple:Person)
RETURN path LIMIT 200;

// ===== 4. 家族世系（用 upstep/dwnstep 控制方向）=====
MATCH path = (p:Person {nameChn:'蘇軾'})-[r:KIN*1..4]-(kin:Person)
WHERE ALL(x IN r WHERE x.marstep = 0)
RETURN path LIMIT 300;

// ===== 5. 婚姻网络：某地的家族联姻（地方精英研究）=====
MATCH (a:Person)-[:LIVED_IN {typeChn:'籍貫(基本地址)'}]->(place:Place {nameChn:'婺源'})
MATCH (a)-[m:KIN]->(b:Person) WHERE m.marstep = 1 AND m.upstep = 0 AND m.dwnstep = 0
RETURN a.surnameChn AS 夫家, b.surnameChn AS 妻家, count(*) AS 通婚次数
ORDER BY 通婚次数 DESC LIMIT 30;

// ===== 6. 宦游轨迹（地图视图数据源）=====
MATCH (p:Person {nameChn:'蘇軾'})-[r:POSTED_AT]->(a:Place)
WHERE a.location IS NOT NULL
RETURN a.nameChn, a.x, a.y, r.firstYear, r.lastYear
ORDER BY coalesce(r.firstYear, 9999);

// ===== 7. 地图范围查询（前端拖动地图时调用）=====
MATCH (a:Place)<-[:LIVED_IN {typeChn:'籍貫(基本地址)'}]-(p:Person)
WHERE point.withinBBox(a.location, point({longitude:118.0, latitude:28.0}),
                                    point({longitude:121.0, latitude:31.0}))
  AND p.dynastyChn = '宋'
RETURN a.nameChn, a.x, a.y, count(p) AS 人数 ORDER BY 人数 DESC;

// ===== 8. 科举同年网络（库里没有，需生成的隐含边）=====
MATCH (a:Person)-[e1:ENTERED_VIA]->(t:EntryType)<-[e2:ENTERED_VIA]-(b:Person)
WHERE t.descChn CONTAINS '進士' AND e1.year = e2.year AND e1.year IS NOT NULL
  AND id(a) < id(b)
MERGE (a)-[:SAME_EXAM_YEAR {year:e1.year}]-(b);

// ===== 9. 全文检索（搜索框后端）=====
CALL db.index.fulltext.queryNodes('personSearch', $q) YIELD node, score
RETURN node.personId, node.nameChn, node.dynastyChn, node.indexYear, score
ORDER BY score DESC LIMIT 20;

// ===== 10. GDS：宋代交往网络的社群发现 =====
CALL gds.graph.project.cypher('song',
  'MATCH (p:Person) WHERE p.dynastyChn = "宋" RETURN id(p) AS id',
  'MATCH (a:Person)-[r:ASSOC]-(b:Person)
   WHERE a.dynastyChn="宋" AND b.dynastyChn="宋"
   RETURN id(a) AS source, id(b) AS target');

CALL gds.louvain.stream('song') YIELD nodeId, communityId
WITH communityId, collect(gds.util.asNode(nodeId).nameChn) AS 成员
WHERE size(成员) > 20
RETURN communityId, size(成员) AS 规模, 成员[0..15] AS 代表人物
ORDER BY 规模 DESC;

// ===== 11. GDS：中介中心性——谁是网络的桥梁 =====
CALL gds.betweenness.stream('song') YIELD nodeId, score
RETURN gds.util.asNode(nodeId).nameChn AS 人物, score
ORDER BY score DESC LIMIT 25;
