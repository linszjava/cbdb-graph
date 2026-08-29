package cbdb.graph.repository;

import cbdb.graph.dto.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.neo4j.core.Neo4jClient;
import org.springframework.stereotype.Repository;

import java.util.*;

/**
 * 所有 Cypher 集中在此。刻意不使用 OGM 实体映射 ——
 * 知识图谱返回的是任意形状的子图，映射成固定 POJO 反而处处受限。
 */
@Repository
public class GraphRepository {

    private final Neo4jClient client;

    @Value("${cbdb.ego-node-limit:500}")
    private int egoNodeLimit;

    public GraphRepository(Neo4jClient client) {
        this.client = client;
    }

    // ---------- 检索 ----------

    /**
     * 分级匹配，精确优先。
     * 不用全文索引：Lucene 对中文按单字切分，搜「东坡」会返回一堆带「坡」字的人，
     * 苏轼反而排不进来 —— 这种模糊匹配对人名检索是负价值。
     *   rank 0  本名精确（简体或繁体）
     *   rank 1  别名精确（altSearch 两端补了空格，' 子瞻 ' 即精确匹配）
     *   rank 2  本名前缀
     *   rank 3  别名包含
     */
    private static final String SEARCH = """
            CALL () {
              MATCH (p:Person) WHERE p.nameChn = $q
              RETURN p, 0 AS rank
              UNION
              MATCH (p:Person) WHERE p.altSearch CONTAINS (' ' + $q + ' ')
              RETURN p, 1 AS rank
              UNION
              MATCH (p:Person) WHERE p.nameChn STARTS WITH $q
              RETURN p, 2 AS rank
              UNION
              MATCH (p:Person) WHERE p.altSearch CONTAINS $q
              RETURN p, 3 AS rank
            }
            WITH p, min(rank) AS rank
            RETURN p.personId    AS id,
                   p.nameChn     AS nameChn,
                   p.name        AS name,
                   p.dynastyChn  AS dynasty,
                   p.indexYear   AS indexYear,
                   p.birthYear   AS birthYear,
                   p.deathYear   AS deathYear,
                   p.altLabels   AS altLabels,
                   toFloat(3 - rank) AS score
            ORDER BY rank ASC, coalesce(p.indexYear, 9999) ASC
            LIMIT $limit
            """;

    public List<SearchHit> search(String q, int limit) {
        String term = q == null ? "" : q.trim();
        if (term.isBlank()) return List.of();
        return client.query(SEARCH)
                .bindAll(Map.of("q", term, "limit", limit))
                .fetch().all().stream()
                .map(r -> new SearchHit(
                        num(r.get("id")).longValue(),
                        str(r.get("nameChn")),
                        str(r.get("name")),
                        str(r.get("dynasty")),
                        integer(r.get("indexYear")),
                        integer(r.get("birthYear")),
                        integer(r.get("deathYear")),
                        strings(r.get("altLabels")),
                        num(r.get("score")).doubleValue()))
                .toList();
    }

    // ---------- 人物档案 ----------

    private static final String PERSON = """
            MATCH (p:Person {personId: $id})
            OPTIONAL MATCH (p)-[l:LIVED_IN]->(pl:Place)
            WITH p, collect(DISTINCT {
                     type: l.typeChn, place: pl.nameChn, placeId: pl.addrId,
                     x: pl.x, y: pl.y, firstYear: l.firstYear
                 })[0..25] AS addresses
            OPTIONAL MATCH (p)-[h:HELD_OFFICE]->(o:Office)
            WITH p, addresses, collect(DISTINCT {
                     office: o.officeChn, pinyin: o.officePinyin,
                     firstYear: h.firstYear, lastYear: h.lastYear
                 })[0..60] AS offices
            OPTIONAL MATCH (p)-[e:ENTERED_VIA]->(et:EntryType)
            WITH p, addresses, offices, collect(DISTINCT {
                     entry: et.descChn, year: e.year, rank: e.rank
                 })[0..25] AS entries
            OPTIONAL MATCH (p)-[a:AUTHORED]->(t:Text)
            WITH p, addresses, offices, entries, collect(DISTINCT {
                     title: t.titleChn, role: a.roleChn, year: t.textYear
                 })[0..40] AS texts
            RETURN p.personId    AS id,
                   p.nameChn     AS nameChn,
                   p.name        AS name,
                   p.surnameChn  AS surnameChn,
                   p.dynastyChn  AS dynasty,
                   p.birthYear   AS birthYear,
                   p.deathYear   AS deathYear,
                   p.indexYear   AS indexYear,
                   p.female      AS female,
                   p.notes       AS notes,
                   count { (p)-[:ASSOC]-() } AS assocDegree,
                   count { (p)-[:KIN]-() }   AS kinDegree,
                   p.altLabels   AS altLabels,
                   p.statuses    AS statuses,
                   p.choronym    AS choronym,
                   p.community   AS community,
                   p.betweenness AS betweenness,
                   p.pagerank    AS pagerank,
                   addresses, offices, entries, texts
            """;

    public Optional<PersonDTO> person(long id) {
        return client.query(PERSON)
                .bindAll(Map.of("id", id))
                .fetch().one()
                .map(r -> new PersonDTO(
                        num(r.get("id")).longValue(),
                        str(r.get("nameChn")),
                        str(r.get("name")),
                        str(r.get("surnameChn")),
                        str(r.get("dynasty")),
                        integer(r.get("birthYear")),
                        integer(r.get("deathYear")),
                        integer(r.get("indexYear")),
                        bool(r.get("female")),
                        str(r.get("notes")),
                        strings(r.get("altLabels")),
                        strings(r.get("statuses")),
                        str(r.get("choronym")),
                        num(r.get("assocDegree")).longValue(),
                        num(r.get("kinDegree")).longValue(),
                        integer(r.get("community")),
                        r.get("betweenness") == null ? null : num(r.get("betweenness")).doubleValue(),
                        r.get("pagerank") == null ? null : num(r.get("pagerank")).doubleValue(),
                        maps(r.get("addresses")),
                        maps(r.get("offices")),
                        maps(r.get("entries")),
                        maps(r.get("texts"))));
    }

    // ---------- Ego 网络 ----------

    private static final String EGO = """
            MATCH (p:Person {personId: $id})
            CALL apoc.path.subgraphAll(p, {
                maxLevel: $hops,
                relationshipFilter: $relFilter,
                labelFilter: '+Person',
                limit: $limit
            }) YIELD nodes, relationships
            RETURN
              [n IN nodes | {
                 id: n.personId, label: n.nameChn,
                 dynasty: n.dynastyChn, year: n.indexYear,
                 birthYear: n.birthYear, deathYear: n.deathYear,
                 female: n.female, community: n.community
              }] AS nodes,
              [r IN relationships | {
                 id: elementId(r),
                 source: startNode(r).personId, target: endNode(r).personId,
                 type: type(r), label: r.relChn,
                 year: r.year, sourceRef: r.source, pages: r.pages,
                 textTitle: r.textTitle,
                 upstep: r.upstep, dwnstep: r.dwnstep, marstep: r.marstep
              }] AS edges
            """;

    // 数的是「关联者人数」而非关系条数 —— 同一对人可能有多条边（如楼钥为苏轼作过 9 篇题跋）
    private static final String DEGREE = """
            MATCH (p:Person {personId: $id})
            OPTIONAL MATCH (p)-[:ASSOC|KIN]-(q:Person)
            RETURN count(DISTINCT q) AS degree
            """;

    public GraphDTO egoNetwork(long id, int hops, List<String> relTypes) {
        String relFilter = String.join("|", relTypes.isEmpty() ? List.of("KIN", "ASSOC") : relTypes);

        long degree = client.query(DEGREE).bindAll(Map.of("id", id))
                .fetch().one()
                .map(r -> num(r.get("degree")).longValue())
                .orElse(0L);

        Optional<Map<String, Object>> res = client.query(EGO)
                .bindAll(Map.of("id", id, "hops", hops,
                                "relFilter", relFilter, "limit", egoNodeLimit))
                .fetch().one();

        if (res.isEmpty()) return GraphDTO.empty();

        List<Map<String, Object>> rawNodes = maps(res.get().get("nodes"));
        List<Map<String, Object>> rawEdges = maps(res.get().get("edges"));

        List<NodeDTO> nodes = rawNodes.stream()
                .map(n -> new NodeDTO(
                        num(n.get("id")).longValue(),
                        str(n.get("label")),
                        str(n.get("dynasty")),
                        integer(n.get("year")),
                        integer(n.get("birthYear")),
                        integer(n.get("deathYear")),
                        bool(n.get("female")),
                        integer(n.get("community")),
                        num(n.get("id")).longValue() == id,
                        null))
                .toList();

        Set<Long> present = new HashSet<>();
        nodes.forEach(n -> present.add(n.id()));

        List<EdgeDTO> edges = rawEdges.stream()
                .filter(e -> present.contains(num(e.get("source")).longValue())
                          && present.contains(num(e.get("target")).longValue()))
                .map(e -> new EdgeDTO(
                        str(e.get("id")),
                        num(e.get("source")).longValue(),
                        num(e.get("target")).longValue(),
                        str(e.get("type")),
                        str(e.get("label")),
                        integer(e.get("year")),
                        e.get("sourceRef") == null ? null : num(e.get("sourceRef")).longValue(),
                        str(e.get("pages")), str(e.get("textTitle")),
                        integer(e.get("upstep")), integer(e.get("dwnstep")), integer(e.get("marstep"))))
                .toList();

        boolean truncated = nodes.size() >= egoNodeLimit;
        return new GraphDTO(nodes, edges, truncated, degree);
    }

    // ---------- 关系路径 ----------

    public GraphDTO shortestPath(long from, long to, int maxHops) {
        // Cypher 的变长路径上界不接受参数，此处以校验过的整数拼接
        int hops = Math.max(1, Math.min(maxHops, 8));
        String cypher = """
                MATCH (a:Person {personId: $from}), (b:Person {personId: $to})
                MATCH path = shortestPath((a)-[:ASSOC|KIN*..%d]-(b))
                RETURN
                  [n IN nodes(path) | {
                     id: n.personId, label: n.nameChn,
                     dynasty: n.dynastyChn, year: n.indexYear,
                     birthYear: n.birthYear, deathYear: n.deathYear,
                     female: n.female, community: n.community
                  }] AS nodes,
                  [r IN relationships(path) | {
                     id: elementId(r),
                     source: startNode(r).personId, target: endNode(r).personId,
                     type: type(r), label: r.relChn,
                     year: r.year, sourceRef: r.source, pages: r.pages,
                     textTitle: r.textTitle,
                     upstep: r.upstep, dwnstep: r.dwnstep, marstep: r.marstep
                  }] AS edges
                """.formatted(hops);

        Optional<Map<String, Object>> res = client.query(cypher)
                .bindAll(Map.of("from", from, "to", to))
                .fetch().one();

        if (res.isEmpty()) return GraphDTO.empty();

        List<NodeDTO> nodes = maps(res.get().get("nodes")).stream()
                .map(n -> new NodeDTO(
                        num(n.get("id")).longValue(), str(n.get("label")),
                        str(n.get("dynasty")), integer(n.get("year")),
                        integer(n.get("birthYear")), integer(n.get("deathYear")),
                        bool(n.get("female")), integer(n.get("community")),
                        num(n.get("id")).longValue() == from || num(n.get("id")).longValue() == to,
                        null))
                .toList();

        List<EdgeDTO> edges = maps(res.get().get("edges")).stream()
                .map(e -> new EdgeDTO(
                        str(e.get("id")),
                        num(e.get("source")).longValue(), num(e.get("target")).longValue(),
                        str(e.get("type")), str(e.get("label")), integer(e.get("year")),
                        e.get("sourceRef") == null ? null : num(e.get("sourceRef")).longValue(),
                        str(e.get("pages")), str(e.get("textTitle")),
                        integer(e.get("upstep")), integer(e.get("dwnstep")), integer(e.get("marstep"))))
                .toList();

        return new GraphDTO(nodes, edges, false, nodes.size());
    }


    // ---------- M4 家族世系 ----------

    private static final String LINEAGE = """
            MATCH (p:Person {personId: $id})
            CALL apoc.path.subgraphAll(p, {
                maxLevel: $hops,
                relationshipFilter: 'KIN',
                labelFilter: '+Person',
                limit: $limit
            }) YIELD nodes, relationships
            RETURN
              [n IN nodes | {
                 id: n.personId, label: n.nameChn,
                 dynasty: n.dynastyChn, year: n.indexYear,
                 birthYear: n.birthYear, deathYear: n.deathYear,
                 female: n.female, community: n.community
              }] AS nodes,
              // relationshipFilter 只约束遍历路径，subgraphAll 返回的 relationships
              // 包含结果节点之间的全部类型的边 —— 不在此处筛掉，社会关系会混进世系图
              [r IN relationships WHERE type(r) = 'KIN' | {
                 id: elementId(r),
                 source: startNode(r).personId, target: endNode(r).personId,
                 type: type(r), label: r.relChn,
                 year: r.year, sourceRef: r.source, pages: r.pages,
                 textTitle: r.textTitle,
                 upstep: r.upstep, dwnstep: r.dwnstep, marstep: r.marstep
              }] AS edges
            """;

    public GraphDTO lineage(long id, int hops, int limit) {
        Optional<Map<String, Object>> res = client.query(LINEAGE)
                .bindAll(Map.of("id", id, "hops", hops, "limit", limit))
                .fetch().one();
        if (res.isEmpty()) return GraphDTO.empty();

        List<Map<String, Object>> rawNodes = maps(res.get().get("nodes"));
        List<Map<String, Object>> rawEdges = maps(res.get().get("edges"));

        List<EdgeDTO> edges = rawEdges.stream()
                .map(e -> new EdgeDTO(
                        str(e.get("id")),
                        num(e.get("source")).longValue(), num(e.get("target")).longValue(),
                        str(e.get("type")), str(e.get("label")), integer(e.get("year")),
                        e.get("sourceRef") == null ? null : num(e.get("sourceRef")).longValue(),
                        str(e.get("pages")), str(e.get("textTitle")),
                        integer(e.get("upstep")), integer(e.get("dwnstep")), integer(e.get("marstep"))))
                .toList();

        Map<Long, Integer> gen = generations(id, edges);

        List<NodeDTO> nodes = rawNodes.stream()
                .map(n -> {
                    long nid = num(n.get("id")).longValue();
                    return new NodeDTO(nid, str(n.get("label")),
                            str(n.get("dynasty")), integer(n.get("year")),
                            integer(n.get("birthYear")), integer(n.get("deathYear")),
                            bool(n.get("female")), integer(n.get("community")),
                            nid == id, gen.get(nid));
                })
                .toList();

        return new GraphDTO(nodes, edges, nodes.size() >= limit, nodes.size());
    }

    /** CBDB 用 99 表示「世代距离未详」（直系祖先/直系后裔/未详），不是真实步数。 */
    private static final int STEP_UNKNOWN = 99;

    /**
     * 以 ego 为第 0 代做 BFS 推算世代。
     * CBDB 的 KINSHIP_CODES 自带 up/dwn/mar/col 四维亲属距离向量，
     * 沿一条边 A→B 时 B 的世代 = A 的世代 + dwnstep - upstep；配偶（marstep）同代。
     * 步数为 99 的边不参与推算 —— 那是哨兵值，照算会得出「第 99 代」这种荒谬结果。
     * 只能经由此类边到达的人物，世代留空，由前端归入「世代未详」。
     */
    static Map<Long, Integer> generations(long ego, List<EdgeDTO> edges) {
        Map<Long, List<EdgeDTO>> out = new HashMap<>();
        for (EdgeDTO e : edges) {
            out.computeIfAbsent(e.source(), k -> new ArrayList<>()).add(e);
            out.computeIfAbsent(e.target(), k -> new ArrayList<>()).add(e);
        }
        Map<Long, Integer> gen = new HashMap<>();
        gen.put(ego, 0);
        Deque<Long> queue = new ArrayDeque<>();
        queue.add(ego);
        while (!queue.isEmpty()) {
            long cur = queue.poll();
            int g = gen.get(cur);
            for (EdgeDTO e : out.getOrDefault(cur, List.of())) {
                boolean forward = e.source() == cur;
                long next = forward ? e.target() : e.source();
                if (gen.containsKey(next)) continue;
                int up = e.upstep() == null ? 0 : e.upstep();
                int down = e.dwnstep() == null ? 0 : e.dwnstep();
                if (Math.abs(up) >= STEP_UNKNOWN || Math.abs(down) >= STEP_UNKNOWN) continue;
                int delta = forward ? (down - up) : (up - down);
                gen.put(next, g + delta);
                queue.add(next);
            }
        }
        return gen;
    }

    // ---------- M5 宦游地图 ----------

    private static final String ATLAS = """
            MATCH (p:Person {personId: $id})-[r:POSTED_AT|LIVED_IN]->(a:Place)
            WHERE a.x IS NOT NULL AND a.y IS NOT NULL
            OPTIONAL MATCH (o:Office) WHERE type(r) = 'POSTED_AT' AND o.officeId = r.officeId
            RETURN a.addrId AS id, a.nameChn AS name, a.x AS x, a.y AS y,
                   type(r) AS kind, r.typeChn AS subtype, o.officeChn AS office,
                   r.firstYear AS firstYear, r.lastYear AS lastYear
            ORDER BY coalesce(r.firstYear, 99999)
            """;

    public List<PlaceDTO> atlas(long id) {
        return client.query(ATLAS).bindAll(Map.of("id", id))
                .fetch().all().stream()
                .map(r -> new PlaceDTO(
                        num(r.get("id")).longValue(),
                        str(r.get("name")),
                        num(r.get("x")).doubleValue(),
                        num(r.get("y")).doubleValue(),
                        str(r.get("kind")),
                        str(r.get("subtype")),
                        str(r.get("office")),
                        integer(r.get("firstYear")),
                        integer(r.get("lastYear"))))
                .toList();
    }

    // ---------- M8 史料出处 ----------

    private static final String SOURCE = """
            MATCH (t:Text {textId: $id})
            RETURN t.textId AS textId, t.titleChn AS titleChn,
                   t.title AS title, t.textYear AS textYear
            """;

    public Optional<SourceDTO> source(long textId) {
        return client.query(SOURCE).bindAll(Map.of("id", textId))
                .fetch().one()
                .map(r -> new SourceDTO(
                        num(r.get("textId")).longValue(),
                        str(r.get("titleChn")),
                        str(r.get("title")),
                        integer(r.get("textYear"))));
    }


    // ---------- 科举同年 ----------

    private static final String COHORTS = """
            MATCH (p:Person {personId: $id})-[:SAME_COHORT]->(c:ExamCohort)
            RETURN c.cohortId AS cohortId, c.year AS year,
                   c.entryChn AS entryChn, c.size AS size
            ORDER BY c.size DESC
            """;

    private static final String COHORT_MEMBERS = """
            MATCH (c:ExamCohort {cohortId: $cid})<-[:SAME_COHORT]-(p:Person)
            RETURN p.personId AS id, p.nameChn AS nameChn,
                   p.name AS name, p.dynastyChn AS dynasty, p.indexYear AS indexYear,
                   p.birthYear AS birthYear, p.deathYear AS deathYear,
                   p.altLabels AS altLabels,
                   count { (p)-[:ASSOC]-() } AS deg
            ORDER BY deg DESC
            LIMIT $limit
            """;

    public List<CohortDTO> cohorts(long personId, int memberLimit) {
        List<Map<String, Object>> rows = List.copyOf(
                client.query(COHORTS).bindAll(Map.of("id", personId)).fetch().all());
        List<CohortDTO> out = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            long cid = num(r.get("cohortId")).longValue();
            List<SearchHit> members = client.query(COHORT_MEMBERS)
                    .bindAll(Map.of("cid", cid, "limit", memberLimit))
                    .fetch().all().stream()
                    .map(m -> new SearchHit(
                            num(m.get("id")).longValue(), str(m.get("nameChn")), str(m.get("name")), str(m.get("dynasty")),
                            integer(m.get("indexYear")), integer(m.get("birthYear")),
                            integer(m.get("deathYear")), strings(m.get("altLabels")), 0d))
                    .toList();
            out.add(new CohortDTO(cid, integer(r.get("year")), str(r.get("entryChn")),
                    integer(r.get("size")) == null ? members.size() : integer(r.get("size")),
                    members));
        }
        return out;
    }

    // ---------- 年号纪年 ----------

    private static final String NIANHAO = """
            MATCH (n:NianHao)
            WHERE $year < 0 OR (n.firstYear <= $year AND n.lastYear >= $year)
            RETURN n.nameChn AS nameChn, n.dynastyChn AS dynastyChn,
                   n.firstYear AS firstYear, n.lastYear AS lastYear
            ORDER BY n.firstYear DESC
            """;

    /**
     * year 传 -1 返回全部 647 条，供前端一次性加载后本地换算 ——
     * 档案页上每个年份都发一次请求太碎。
     * 同一年可能跨多个政权（南北朝、宋金对峙），全部返回由前端按朝代择用。
     */
    public List<NianHaoDTO> nianhao(int year) {
        return client.query(NIANHAO).bindAll(Map.of("year", year))
                .fetch().all().stream()
                .map(r -> {
                    int fy = num(r.get("firstYear")).intValue();
                    int nth = year < 0 ? 0 : year - fy + 1;
                    String nm = str(r.get("nameChn"));
                    return new NianHaoDTO(nm, str(r.get("dynastyChn")), fy,
                            num(r.get("lastYear")).intValue(), nth,
                            nth <= 0 ? nm : nm + (nth == 1 ? "元年" : nth + "年"));
                })
                .toList();
    }

    // ---------- 政区层级 ----------

    // ---------- 政区层级 ----------

    /**
     * 一个地方的政区上下文：向上的隶属链、直属下级、以及以此为籍贯的人物。
     * 人数统计要含下辖各级 —— 问「江南西路有多少人」时，答案该包含抚州、临川。
     */
    private static final String PLACE_TREE = """
            MATCH (a:Place {addrId: $id})
            // 向上的隶属链（县 → 州 → 路 → 朝）
            OPTIONAL MATCH up = (a)-[:BELONGS_TO*1..5]->(:Place)
            WITH a, [n IN nodes(up) WHERE n <> a | {id: n.addrId, name: n.nameChn}] AS chain
            WITH a, head(collect(chain)) AS ancestors
            // 直属下级及各自的人物数（含其下辖）
            CALL (a) {
              MATCH (child:Place)-[:BELONGS_TO]->(a)
              CALL (child) {
                MATCH (d:Place)-[:BELONGS_TO*0..3]->(child)
                OPTIONAL MATCH (:Person)-[l:LIVED_IN]->(d) WHERE l.typeChn STARTS WITH '籍贯'
                RETURN count(l) AS cnt
              }
              RETURN collect({id: child.addrId, name: child.nameChn, people: cnt})[0..200] AS children
            }
            // 本级（含下辖）的人物
            CALL (a) {
              MATCH (d:Place)-[:BELONGS_TO*0..4]->(a)
              MATCH (p:Person)-[l:LIVED_IN]->(d) WHERE l.typeChn STARTS WITH '籍贯'
              WITH DISTINCT p
              // 按中介中心性排序，否则取到的前 120 人全是扫描顺序靠前的宗室
              ORDER BY coalesce(p.betweenness, 0) DESC, coalesce(p.indexYear, 9999)
              WITH collect(p) AS ps
              RETURN size(ps) AS total,
                     [x IN ps[0..120] | {
                       id: x.personId, name: x.nameChn,
                       dynasty: x.dynastyChn, year: x.indexYear,
                       birthYear: x.birthYear, deathYear: x.deathYear,
                       deg: x.betweenness
                     }] AS sample
            }
            RETURN a.addrId AS id, a.nameChn AS name,
                   a.x AS x, a.y AS y,
                   a.firstYear AS firstYear, a.lastYear AS lastYear,
                   ancestors, children, total, sample
            """;

    public Optional<Map<String, Object>> placeTree(long addrId) {
        return client.query(PLACE_TREE).bindAll(Map.of("id", addrId)).fetch().one();
    }

    /** 按名称找地方，供政区视图的搜索框用。 */
    private static final String PLACE_SEARCH = """
            MATCH (a:Place) WHERE a.nameChn = $q OR a.nameChn STARTS WITH $q
            OPTIONAL MATCH (a)-[:BELONGS_TO]->(up:Place)
            RETURN a.addrId AS id, a.nameChn AS name,
                   a.firstYear AS firstYear, a.lastYear AS lastYear,
                   up.nameChn AS parent,
                   CASE WHEN a.nameChn = $q THEN 0 ELSE 1 END AS rank
            ORDER BY rank, a.firstYear
            LIMIT $limit
            """;

    public List<Map<String, Object>> searchPlaces(String q, int limit) {
        if (q == null || q.isBlank()) return List.of();
        return List.copyOf(client.query(PLACE_SEARCH)
                .bindAll(Map.of("q", q.trim(), "limit", limit)).fetch().all());
    }

    // ---------- 群体网络 ----------

    /**
     * 取一个群体（按身份 / 郡望 / 朝代）的内部交往网络。
     * 只保留群体内部的边 —— 要看的是这批人彼此如何相连，不是他们各自的邻居。
     */
    private static final String GROUP = """
            MATCH (p:Person)
            WHERE ($status   IS NULL OR $status   IN p.statuses)
              AND ($choronym IS NULL OR p.choronym = $choronym)
              AND ($dynasty  IS NULL OR p.dynastyChn = $dynasty)
            WITH collect(p)[0..$limit] AS ps
            UNWIND ps AS p
            WITH ps, p
            OPTIONAL MATCH (p)-[r:ASSOC]-(q:Person) WHERE q IN ps
            WITH ps, collect(DISTINCT r) AS rels
            RETURN
              [n IN ps | {
                 id: n.personId, label: n.nameChn,
                 dynasty: n.dynastyChn, year: n.indexYear,
                 birthYear: n.birthYear, deathYear: n.deathYear,
                 female: n.female, community: n.community
              }] AS nodes,
              [r IN rels | {
                 id: elementId(r),
                 source: startNode(r).personId, target: endNode(r).personId,
                 type: type(r), label: r.relChn,
                 year: r.year, sourceRef: r.source, pages: r.pages,
                 textTitle: r.textTitle,
                 upstep: r.upstep, dwnstep: r.dwnstep, marstep: r.marstep
              }] AS edges
            """;

    public GraphDTO group(String status, String choronym, String dynasty, int limit) {
        Map<String, Object> params = new HashMap<>();
        params.put("status", status);
        params.put("choronym", choronym);
        params.put("dynasty", dynasty);
        params.put("limit", limit);

        Optional<Map<String, Object>> res = client.query(GROUP).bindAll(params).fetch().one();
        if (res.isEmpty()) return GraphDTO.empty();

        List<NodeDTO> nodes = maps(res.get().get("nodes")).stream()
                .map(n -> new NodeDTO(
                        num(n.get("id")).longValue(), str(n.get("label")),
                        str(n.get("dynasty")), integer(n.get("year")),
                        integer(n.get("birthYear")), integer(n.get("deathYear")),
                        bool(n.get("female")), integer(n.get("community")), false, null))
                .toList();

        Set<Long> present = new HashSet<>();
        nodes.forEach(n -> present.add(n.id()));

        List<EdgeDTO> edges = maps(res.get().get("edges")).stream()
                .filter(e -> present.contains(num(e.get("source")).longValue())
                          && present.contains(num(e.get("target")).longValue()))
                .map(e -> new EdgeDTO(
                        str(e.get("id")),
                        num(e.get("source")).longValue(), num(e.get("target")).longValue(),
                        str(e.get("type")), str(e.get("label")), integer(e.get("year")),
                        e.get("sourceRef") == null ? null : num(e.get("sourceRef")).longValue(),
                        str(e.get("pages")), str(e.get("textTitle")),
                        integer(e.get("upstep")), integer(e.get("dwnstep")), integer(e.get("marstep"))))
                .toList();

        return new GraphDTO(nodes, edges, nodes.size() >= limit, nodes.size());
    }

    /** 群体可选项：身份、郡望各取最常见的若干个，供前端做下拉。 */
    public Map<String, List<Map<String, Object>>> groupOptions() {
        var statuses = client.query("""
                MATCH (p:Person) WHERE p.statuses IS NOT NULL
                UNWIND p.statuses AS s
                WITH s, count(*) AS n WHERE n >= 50
                RETURN s AS value, n ORDER BY n DESC LIMIT 60
                """).fetch().all();
        var chors = client.query("""
                MATCH (p:Person) WHERE p.choronym IS NOT NULL
                WITH p.choronym AS c, count(*) AS n WHERE n >= 30
                RETURN c AS value, n ORDER BY n DESC LIMIT 40
                """).fetch().all();
        return Map.of("statuses", List.copyOf(statuses), "choronyms", List.copyOf(chors));
    }


    // ---------- 社群画像 ----------

    private static final String COMMUNITY = """
            MATCH (p:Person {community: $cid})
            WITH collect(p) AS ps
            WITH ps, size(ps) AS total
            // 代表人物：按中介中心性，这批人最能代表该社群
            CALL (ps) {
              UNWIND ps AS p
              WITH p ORDER BY coalesce(p.betweenness, 0) DESC LIMIT 12
              RETURN collect({id: p.personId, name: p.nameChn,
                              betweenness: p.betweenness}) AS members
            }
            CALL (ps) {
              UNWIND ps AS p
              WITH p WHERE p.indexYear IS NOT NULL
              RETURN min(p.indexYear) AS eraFrom, max(p.indexYear) AS eraTo,
                     toInteger(percentileCont(p.indexYear, 0.5)) AS eraMedian
            }
            CALL (ps) {
              UNWIND ps AS p
              WITH p.dynastyChn AS d WHERE d IS NOT NULL
              RETURN d ORDER BY d LIMIT 1
            }
            CALL (ps) {
              UNWIND ps AS p
              WITH p WHERE p.statuses IS NOT NULL
              UNWIND p.statuses AS s
              WITH s, count(*) AS n ORDER BY n DESC LIMIT 6
              RETURN collect({value: s, n: n}) AS statuses
            }
            CALL (ps) {
              UNWIND ps AS p
              MATCH (p)-[l:LIVED_IN]->(pl:Place) WHERE l.typeChn STARTS WITH '籍贯'
              WITH pl.nameChn AS place, count(*) AS n ORDER BY n DESC LIMIT 6
              RETURN collect({value: place, n: n}) AS places
            }
            RETURN total, members, eraFrom, eraTo, eraMedian, d AS dynasty,
                   statuses, places
            """;

    public Optional<CommunityDTO> community(long cid) {
        return client.query(COMMUNITY).bindAll(Map.of("cid", cid))
                .fetch().one()
                .map(r -> {
                    List<Map<String, Object>> members = maps(r.get("members"));
                    // 标识取前三位代表人物 —— 史学命名（「道学集团」）不是数据能给的
                    String label = members.stream().limit(3)
                            .map(m -> str(m.get("name")))
                            .filter(Objects::nonNull)
                            .reduce((a, b) -> a + "·" + b).orElse("社群 " + cid);
                    return new CommunityDTO(
                            cid, integer(r.get("total")) == null ? 0 : integer(r.get("total")),
                            label, str(r.get("dynasty")),
                            integer(r.get("eraFrom")), integer(r.get("eraTo")),
                            integer(r.get("eraMedian")),
                            members, maps(r.get("statuses")), maps(r.get("places")));
                });
    }

    // ---------- 工具 ----------





    /** Lucene 语法字符会让全文检索抛异常，逐个转义。 */
    static String escapeLucene(String raw) {
        if (raw == null) return "";
        StringBuilder sb = new StringBuilder();
        for (char c : raw.trim().toCharArray()) {
            if ("+-&|!(){}[]^\"~*?:\\/".indexOf(c) >= 0) sb.append('\\');
            sb.append(c);
        }
        return sb.toString();
    }

    private static Number num(Object o) { return o instanceof Number n ? n : 0; }
    private static String str(Object o) { return o == null ? null : o.toString(); }
    private static Boolean bool(Object o) { return o instanceof Boolean b ? b : null; }
    private static Integer integer(Object o) { return o instanceof Number n ? n.intValue() : null; }

    /** neo4j 的 string[] 属性回来是 List<Object>，统一转成 List<String> */
    private static List<String> strings(Object o) {
        if (!(o instanceof List<?> list)) return List.of();
        return list.stream().filter(Objects::nonNull).map(Object::toString).toList();
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> maps(Object o) {
        if (!(o instanceof List<?> list)) return List.of();
        return list.stream()
                .filter(Map.class::isInstance)
                .map(x -> (Map<String, Object>) x)
                .filter(m -> !m.isEmpty())
                .toList();
    }
}
