package cbdb.graph.service;

import cbdb.graph.dto.GraphDTO;
import cbdb.graph.dto.PersonDTO;
import cbdb.graph.dto.CohortDTO;
import cbdb.graph.dto.CommunityDTO;
import cbdb.graph.dto.NianHaoDTO;
import cbdb.graph.dto.PlaceDTO;
import cbdb.graph.dto.SourceDTO;
import java.util.Map;
import cbdb.graph.repository.GraphRepository;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Optional;

/**
 * 缓存层单独成 Bean —— Spring 的 @Cacheable 走代理，同类内部自调用不会触发缓存。
 * 参数在 GraphService 里已归一化，此处保证非 null，缓存键表达式才安全。
 */
@Component
public class CachedQueries {

    private final GraphRepository repo;

    public CachedQueries(GraphRepository repo) {
        this.repo = repo;
    }

    @Cacheable(value = "person", key = "#id")
    public Optional<PersonDTO> person(long id) {
        return repo.person(id);
    }

    /** relKey 是逗号连接的关系类型，已归一化排序，可直接作为缓存键的一部分。 */
    @Cacheable(value = "ego", key = "#id + ':' + #hops + ':' + #relKey")
    public GraphDTO ego(long id, int hops, String relKey) {
        return repo.egoNetwork(id, hops, List.of(relKey.split(",")));
    }

    @Cacheable(value = "path", key = "#from + '>' + #to")
    public GraphDTO path(long from, long to) {
        return repo.shortestPath(from, to, 6);
    }

    @Cacheable(value = "lineage", key = "#id + ':' + #hops")
    public GraphDTO lineage(long id, int hops) {
        return repo.lineage(id, hops, 400);
    }

    @Cacheable(value = "atlas", key = "#id")
    public List<PlaceDTO> atlas(long id) {
        return repo.atlas(id);
    }

    @Cacheable(value = "source", key = "#textId")
    public Optional<SourceDTO> source(long textId) {
        return repo.source(textId);
    }

    @Cacheable(value = "cohort", key = "#id")
    public List<CohortDTO> cohorts(long id) {
        return repo.cohorts(id, 200);
    }

    @Cacheable(value = "nianhao", key = "#year")
    public List<NianHaoDTO> nianhao(int year) {
        return repo.nianhao(year);
    }

    @Cacheable(value = "community", key = "#cid")
    public Optional<CommunityDTO> community(long cid) {
        return repo.community(cid);
    }

    @Cacheable(value = "placeTree", key = "#addrId")
    public Optional<Map<String, Object>> placeTree(long addrId) {
        return repo.placeTree(addrId);
    }
}
