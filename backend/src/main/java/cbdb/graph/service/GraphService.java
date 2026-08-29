package cbdb.graph.service;

import cbdb.graph.dto.*;
import cbdb.graph.repository.GraphRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;

/** 参数归一化与截断策略；实际查询与缓存交给 CachedQueries。 */
@Service
public class GraphService {

    private static final List<String> ALLOWED_RELS = List.of("ASSOC", "KIN");

    private final GraphRepository repo;
    private final CachedQueries cache;

    @Value("${cbdb.max-hops:3}")
    private int maxHops;

    @Value("${cbdb.search-limit:25}")
    private int searchLimit;

    public GraphService(GraphRepository repo, CachedQueries cache) {
        this.repo = repo;
        this.cache = cache;
    }

    public List<SearchHit> search(String q, Integer limit) {
        int n = limit == null ? searchLimit : Math.max(1, Math.min(limit, 100));
        return repo.search(q, n);
    }

    public Optional<PersonDTO> person(long id) {
        return cache.person(id);
    }

    public GraphDTO egoNetwork(long id, Integer hops, List<String> relTypes) {
        int h = hops == null ? 1 : Math.max(1, Math.min(hops, maxHops));

        // 归一化：大写、白名单过滤、排序去重 —— 保证同一请求命中同一缓存键
        List<String> rels = (relTypes == null ? List.<String>of() : relTypes).stream()
                .filter(java.util.Objects::nonNull)
                .map(s -> s.trim().toUpperCase())
                .filter(ALLOWED_RELS::contains)
                .distinct().sorted().toList();
        if (rels.isEmpty()) rels = ALLOWED_RELS;

        return cache.ego(id, h, String.join(",", rels));
    }

    public GraphDTO shortestPath(long from, long to) {
        return cache.path(from, to);
    }

    /** 世系默认 3 代 —— 再往外亲属边会指数膨胀且史料可信度下降。 */
    public GraphDTO lineage(long id, Integer hops) {
        int h = hops == null ? 3 : Math.max(1, Math.min(hops, 4));
        return cache.lineage(id, h);
    }

    public List<PlaceDTO> atlas(long id) {
        return cache.atlas(id);
    }

    public Optional<SourceDTO> source(long textId) {
        return cache.source(textId);
    }

    public Optional<CommunityDTO> community(long cid) {
        return cache.community(cid);
    }

    public List<CohortDTO> cohorts(long id) {
        return cache.cohorts(id);
    }

    public List<NianHaoDTO> nianhao(int year) {
        return cache.nianhao(year);
    }

    public Optional<java.util.Map<String, Object>> placeTree(long addrId) {
        return cache.placeTree(addrId);
    }

    /** 群体网络。三个条件可叠加，至少要给一个，否则会把全库拉进来。 */
    public GraphDTO group(String status, String choronym, String dynasty, Integer limit) {
        if (blank(status) && blank(choronym) && blank(dynasty)) return GraphDTO.empty();
        int n = limit == null ? 600 : Math.max(10, Math.min(limit, 2000));
        return repo.group(nz(status), nz(choronym), nz(dynasty), n);
    }

    public List<java.util.Map<String, Object>> searchPlaces(String q) {
        return repo.searchPlaces(q, 25);
    }

    public java.util.Map<String, List<java.util.Map<String, Object>>> groupOptions() {
        return repo.groupOptions();
    }

    private static boolean blank(String s) { return s == null || s.isBlank(); }
    private static String nz(String s) { return blank(s) ? null : s.trim(); }
}
