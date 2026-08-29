// ================= CBDB 数据质量审计 =================
// 检出库中自相矛盾的记载，供人工核验。本脚本只读，不做任何修改。
// 用法：docker exec -i neo4j cypher-shell -u neo4j -p $NEO4J_PASSWORD < neo4j/audit.cypher
//
// 注意：朝代「未详」在 DYNASTIES 表里 c_start=c_end=0，
//       凡涉及朝代区间的规则都必须排除，否则会产生大量误报。

// ---- 规则 1：生年与世代方向矛盾 ----
MATCH (a:Person)-[r:KIN]->(b:Person)
WHERE a.birthYear IS NOT NULL AND b.birthYear IS NOT NULL
  AND coalesce(r.upstep,0) < 99 AND coalesce(r.dwnstep,0) < 99
  AND ((coalesce(r.upstep,0) > 0 AND b.birthYear > a.birthYear) OR
       (coalesce(r.dwnstep,0) > 0 AND b.birthYear < a.birthYear))
RETURN '规则1 生年与世代矛盾' AS 规则, a.personId AS 甲id, a.nameChn AS 甲,
       a.birthYear AS 甲生年, r.relChn AS 记载关系, b.personId AS 乙id,
       b.nameChn AS 乙, b.birthYear AS 乙生年
ORDER BY abs(b.birthYear - a.birthYear) DESC LIMIT 50;

// ---- 规则 2：朝代与世代方向矛盾 ----
MATCH (a:Person)-[r:KIN]->(b:Person)
WHERE a.dynStart > 0 AND a.dynEnd > 0 AND b.dynStart > 0 AND b.dynEnd > 0
  AND coalesce(r.upstep,0) < 99 AND coalesce(r.dwnstep,0) < 99
  AND ((coalesce(r.upstep,0) > 0 AND b.dynStart > a.dynEnd) OR
       (coalesce(r.dwnstep,0) > 0 AND b.dynEnd < a.dynStart))
WITH a, r, b,
     CASE WHEN coalesce(r.upstep,0) > 0 THEN b.dynStart - a.dynEnd
          ELSE a.dynStart - b.dynEnd END AS 相隔
RETURN '规则2 朝代与世代矛盾' AS 规则, a.personId AS 甲id, a.nameChn AS 甲,
       a.dynastyChn AS 甲朝, r.relChn AS 记载关系, b.personId AS 乙id,
       b.nameChn AS 乙, b.dynastyChn AS 乙朝, 相隔
ORDER BY 相隔 DESC LIMIT 50;

// ---- 规则 3：卒年早于生年 ----
MATCH (p:Person) WHERE p.deathYear < p.birthYear
RETURN '规则3 卒年早于生年' AS 规则, p.personId AS id, p.nameChn AS 姓名,
       p.dynastyChn AS 朝代, p.birthYear AS 生年, p.deathYear AS 卒年;

// ---- 规则 4：寿命超过 110 岁 ----
// 部分是传世记载本身如此（如释从谂、王世芳），非必然错误，需逐条判断
MATCH (p:Person) WHERE p.deathYear - p.birthYear > 110
RETURN '规则4 寿命逾110' AS 规则, p.personId AS id, p.nameChn AS 姓名,
       p.dynastyChn AS 朝代, p.birthYear AS 生年, p.deathYear AS 卒年,
       p.deathYear - p.birthYear AS 寿数
ORDER BY 寿数 DESC;

// ---- 规则 5：父子生年差 <12 或 >70 ----
MATCH (a:Person)-[r:KIN]->(b:Person)
WHERE r.rel = 'F' AND a.birthYear IS NOT NULL AND b.birthYear IS NOT NULL
WITH a, b, a.birthYear - b.birthYear AS 父子差
WHERE 父子差 < 12 OR 父子差 > 70
RETURN '规则5 父子年差异常' AS 规则, a.personId AS 子id, a.nameChn AS 子,
       a.birthYear AS 子生年, b.personId AS 父id, b.nameChn AS 父,
       b.birthYear AS 父生年, 父子差
ORDER BY abs(父子差) DESC LIMIT 50;
