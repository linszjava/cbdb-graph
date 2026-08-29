// ============ GDS 预计算（M7）============
// 分朝代计算社群与中心性，结果写回节点属性供前端着色与排序。
//
// 为何必须分朝代：全库人物七成是明清，但交往边压倒性集中在宋，
// 混在一起算出的社群与中心性没有史学意义。
//
// 为何要加偏移量：各朝代是独立投影，Louvain 的 communityId 都从 0 附近起编，
// 跨朝代必然撞号（实测 73 个 ID 被复用）。给每朝代一个百万级基数即可隔离。
//
// import 会清空数据库，故本脚本必须每次重导后重跑。

MATCH (p:Person) WHERE p.community IS NOT NULL OR p.betweenness IS NOT NULL
CALL (p) { REMOVE p.community, p.betweenness, p.pagerank, p.communityRaw }
IN TRANSACTIONS OF 20000 ROWS;

CALL gds.graph.list() YIELD graphName
CALL (graphName) { CALL gds.graph.drop(graphName) YIELD graphName AS g RETURN g }
RETURN count(*) AS 清理的旧投影;

// ---------- 宋 （社群 ID 基数 1000000）----------
MATCH (a:Person)-[:ASSOC]-(b:Person)
WHERE a.dynastyChn = '宋' AND b.dynastyChn = '宋'
RETURN gds.graph.project('g_宋', a, b);

CALL gds.louvain.write('g_宋', {writeProperty: 'communityRaw'})
YIELD communityCount, modularity
RETURN '宋' AS 朝代, communityCount AS 社群数, round(modularity*1000)/1000 AS 模块度;

MATCH (p:Person {dynastyChn: '宋'}) WHERE p.communityRaw IS NOT NULL
CALL (p) { SET p.community = 1000000 + p.communityRaw REMOVE p.communityRaw }
IN TRANSACTIONS OF 20000 ROWS;

CALL gds.betweenness.write('g_宋', {writeProperty: 'betweenness'}) YIELD nodePropertiesWritten
RETURN '宋' AS 朝代, nodePropertiesWritten AS 中介中心性写入数;

CALL gds.pageRank.write('g_宋', {writeProperty: 'pagerank'}) YIELD nodePropertiesWritten
RETURN '宋' AS 朝代, nodePropertiesWritten AS PageRank写入数;

CALL gds.graph.drop('g_宋') YIELD graphName RETURN graphName AS 已释放;

// ---------- 明 （社群 ID 基数 2000000）----------
MATCH (a:Person)-[:ASSOC]-(b:Person)
WHERE a.dynastyChn = '明' AND b.dynastyChn = '明'
RETURN gds.graph.project('g_明', a, b);

CALL gds.louvain.write('g_明', {writeProperty: 'communityRaw'})
YIELD communityCount, modularity
RETURN '明' AS 朝代, communityCount AS 社群数, round(modularity*1000)/1000 AS 模块度;

MATCH (p:Person {dynastyChn: '明'}) WHERE p.communityRaw IS NOT NULL
CALL (p) { SET p.community = 2000000 + p.communityRaw REMOVE p.communityRaw }
IN TRANSACTIONS OF 20000 ROWS;

CALL gds.betweenness.write('g_明', {writeProperty: 'betweenness'}) YIELD nodePropertiesWritten
RETURN '明' AS 朝代, nodePropertiesWritten AS 中介中心性写入数;

CALL gds.pageRank.write('g_明', {writeProperty: 'pagerank'}) YIELD nodePropertiesWritten
RETURN '明' AS 朝代, nodePropertiesWritten AS PageRank写入数;

CALL gds.graph.drop('g_明') YIELD graphName RETURN graphName AS 已释放;

// ---------- 唐 （社群 ID 基数 3000000）----------
MATCH (a:Person)-[:ASSOC]-(b:Person)
WHERE a.dynastyChn = '唐' AND b.dynastyChn = '唐'
RETURN gds.graph.project('g_唐', a, b);

CALL gds.louvain.write('g_唐', {writeProperty: 'communityRaw'})
YIELD communityCount, modularity
RETURN '唐' AS 朝代, communityCount AS 社群数, round(modularity*1000)/1000 AS 模块度;

MATCH (p:Person {dynastyChn: '唐'}) WHERE p.communityRaw IS NOT NULL
CALL (p) { SET p.community = 3000000 + p.communityRaw REMOVE p.communityRaw }
IN TRANSACTIONS OF 20000 ROWS;

CALL gds.betweenness.write('g_唐', {writeProperty: 'betweenness'}) YIELD nodePropertiesWritten
RETURN '唐' AS 朝代, nodePropertiesWritten AS 中介中心性写入数;

CALL gds.pageRank.write('g_唐', {writeProperty: 'pagerank'}) YIELD nodePropertiesWritten
RETURN '唐' AS 朝代, nodePropertiesWritten AS PageRank写入数;

CALL gds.graph.drop('g_唐') YIELD graphName RETURN graphName AS 已释放;

// ---------- 元 （社群 ID 基数 4000000）----------
MATCH (a:Person)-[:ASSOC]-(b:Person)
WHERE a.dynastyChn = '元' AND b.dynastyChn = '元'
RETURN gds.graph.project('g_元', a, b);

CALL gds.louvain.write('g_元', {writeProperty: 'communityRaw'})
YIELD communityCount, modularity
RETURN '元' AS 朝代, communityCount AS 社群数, round(modularity*1000)/1000 AS 模块度;

MATCH (p:Person {dynastyChn: '元'}) WHERE p.communityRaw IS NOT NULL
CALL (p) { SET p.community = 4000000 + p.communityRaw REMOVE p.communityRaw }
IN TRANSACTIONS OF 20000 ROWS;

CALL gds.betweenness.write('g_元', {writeProperty: 'betweenness'}) YIELD nodePropertiesWritten
RETURN '元' AS 朝代, nodePropertiesWritten AS 中介中心性写入数;

CALL gds.pageRank.write('g_元', {writeProperty: 'pagerank'}) YIELD nodePropertiesWritten
RETURN '元' AS 朝代, nodePropertiesWritten AS PageRank写入数;

CALL gds.graph.drop('g_元') YIELD graphName RETURN graphName AS 已释放;

// ---------- 清 （社群 ID 基数 5000000）----------
MATCH (a:Person)-[:ASSOC]-(b:Person)
WHERE a.dynastyChn = '清' AND b.dynastyChn = '清'
RETURN gds.graph.project('g_清', a, b);

CALL gds.louvain.write('g_清', {writeProperty: 'communityRaw'})
YIELD communityCount, modularity
RETURN '清' AS 朝代, communityCount AS 社群数, round(modularity*1000)/1000 AS 模块度;

MATCH (p:Person {dynastyChn: '清'}) WHERE p.communityRaw IS NOT NULL
CALL (p) { SET p.community = 5000000 + p.communityRaw REMOVE p.communityRaw }
IN TRANSACTIONS OF 20000 ROWS;

CALL gds.betweenness.write('g_清', {writeProperty: 'betweenness'}) YIELD nodePropertiesWritten
RETURN '清' AS 朝代, nodePropertiesWritten AS 中介中心性写入数;

CALL gds.pageRank.write('g_清', {writeProperty: 'pagerank'}) YIELD nodePropertiesWritten
RETURN '清' AS 朝代, nodePropertiesWritten AS PageRank写入数;

CALL gds.graph.drop('g_清') YIELD graphName RETURN graphName AS 已释放;

// ---------- 索引与核对 ----------
CREATE INDEX person_community IF NOT EXISTS FOR (p:Person) ON (p.community);

MATCH (p:Person) WHERE p.community IS NOT NULL
WITH p.community AS c, collect(DISTINCT p.dynastyChn) AS dys
RETURN count(*) AS 社群总数, sum(CASE WHEN size(dys) > 1 THEN 1 ELSE 0 END) AS 跨朝代撞号数;

// ---------- 时序中心性 ----------
// 按 50 年窗口滚动计算中介中心性，看权力网络的世代转移。
// 只对宋代做（交往边最密），且不写回节点属性 —— 每个窗口一套属性会把 schema 撑爆，
// 真正要的输出是「每个时期的枢纽人物是谁」这张表。

MATCH (a:Person)-[:ASSOC]-(b:Person)
WHERE a.dynastyChn = '宋' AND b.dynastyChn = '宋'
  AND a.indexYear >= 960 AND a.indexYear <= 1039
  AND b.indexYear >= 960 AND b.indexYear <= 1039
RETURN gds.graph.project('w_960', a, b);

CALL gds.betweenness.stream('w_960') YIELD nodeId, score
WITH gds.util.asNode(nodeId) AS p, score WHERE score > 0
RETURN '960–1039' AS 时期, collect(p.nameChn)[0..8] AS 枢纽人物
ORDER BY 时期;

CALL gds.graph.drop('w_960') YIELD graphName RETURN graphName AS 已释放;

MATCH (a:Person)-[:ASSOC]-(b:Person)
WHERE a.dynastyChn = '宋' AND b.dynastyChn = '宋'
  AND a.indexYear >= 1010 AND a.indexYear <= 1089
  AND b.indexYear >= 1010 AND b.indexYear <= 1089
RETURN gds.graph.project('w_1010', a, b);

CALL gds.betweenness.stream('w_1010') YIELD nodeId, score
WITH gds.util.asNode(nodeId) AS p, score WHERE score > 0
RETURN '1010–1089' AS 时期, collect(p.nameChn)[0..8] AS 枢纽人物
ORDER BY 时期;

CALL gds.graph.drop('w_1010') YIELD graphName RETURN graphName AS 已释放;

MATCH (a:Person)-[:ASSOC]-(b:Person)
WHERE a.dynastyChn = '宋' AND b.dynastyChn = '宋'
  AND a.indexYear >= 1060 AND a.indexYear <= 1139
  AND b.indexYear >= 1060 AND b.indexYear <= 1139
RETURN gds.graph.project('w_1060', a, b);

CALL gds.betweenness.stream('w_1060') YIELD nodeId, score
WITH gds.util.asNode(nodeId) AS p, score WHERE score > 0
RETURN '1060–1139' AS 时期, collect(p.nameChn)[0..8] AS 枢纽人物
ORDER BY 时期;

CALL gds.graph.drop('w_1060') YIELD graphName RETURN graphName AS 已释放;

MATCH (a:Person)-[:ASSOC]-(b:Person)
WHERE a.dynastyChn = '宋' AND b.dynastyChn = '宋'
  AND a.indexYear >= 1110 AND a.indexYear <= 1189
  AND b.indexYear >= 1110 AND b.indexYear <= 1189
RETURN gds.graph.project('w_1110', a, b);

CALL gds.betweenness.stream('w_1110') YIELD nodeId, score
WITH gds.util.asNode(nodeId) AS p, score WHERE score > 0
RETURN '1110–1189' AS 时期, collect(p.nameChn)[0..8] AS 枢纽人物
ORDER BY 时期;

CALL gds.graph.drop('w_1110') YIELD graphName RETURN graphName AS 已释放;

MATCH (a:Person)-[:ASSOC]-(b:Person)
WHERE a.dynastyChn = '宋' AND b.dynastyChn = '宋'
  AND a.indexYear >= 1160 AND a.indexYear <= 1239
  AND b.indexYear >= 1160 AND b.indexYear <= 1239
RETURN gds.graph.project('w_1160', a, b);

CALL gds.betweenness.stream('w_1160') YIELD nodeId, score
WITH gds.util.asNode(nodeId) AS p, score WHERE score > 0
RETURN '1160–1239' AS 时期, collect(p.nameChn)[0..8] AS 枢纽人物
ORDER BY 时期;

CALL gds.graph.drop('w_1160') YIELD graphName RETURN graphName AS 已释放;

MATCH (a:Person)-[:ASSOC]-(b:Person)
WHERE a.dynastyChn = '宋' AND b.dynastyChn = '宋'
  AND a.indexYear >= 1210 AND a.indexYear <= 1289
  AND b.indexYear >= 1210 AND b.indexYear <= 1289
RETURN gds.graph.project('w_1210', a, b);

CALL gds.betweenness.stream('w_1210') YIELD nodeId, score
WITH gds.util.asNode(nodeId) AS p, score WHERE score > 0
RETURN '1210–1289' AS 时期, collect(p.nameChn)[0..8] AS 枢纽人物
ORDER BY 时期;

CALL gds.graph.drop('w_1210') YIELD graphName RETURN graphName AS 已释放;
