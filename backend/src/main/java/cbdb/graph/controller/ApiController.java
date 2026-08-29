package cbdb.graph.controller;

import cbdb.graph.dto.*;
import cbdb.graph.service.GraphService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api")
public class ApiController {

    private final GraphService service;

    public ApiController(GraphService service) {
        this.service = service;
    }

    /** M1 检索：中文按单字切分，简体繁体皆可命中。 */
    @GetMapping("/search")
    public List<SearchHit> search(@RequestParam String q,
                                  @RequestParam(required = false) Integer limit) {
        return service.search(q, limit);
    }

    /** M2 人物档案。 */
    @GetMapping("/person/{id}")
    public ResponseEntity<PersonDTO> person(@PathVariable long id) {
        return service.person(id)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /** M3 ego 网络。relTypes 可传 KIN / ASSOC，留空则两者都要。 */
    @GetMapping("/ego/{id}")
    public GraphDTO ego(@PathVariable long id,
                        @RequestParam(required = false) Integer hops,
                        @RequestParam(required = false) List<String> relTypes) {
        return service.egoNetwork(id, hops, relTypes);
    }

    /** M6 关系路径。 */
    @GetMapping("/path")
    public GraphDTO path(@RequestParam long from, @RequestParam long to) {
        return service.shortestPath(from, to);
    }

    /** M4 家族世系：节点带 generation，ego 为第 0 代，负数为长辈。 */
    @GetMapping("/lineage/{id}")
    public GraphDTO lineage(@PathVariable long id,
                            @RequestParam(required = false) Integer hops) {
        return service.lineage(id, hops);
    }

    /** M5 宦游地图：任职地与居址的地理落点。 */
    @GetMapping("/atlas/{id}")
    public List<PlaceDTO> atlas(@PathVariable long id) {
        return service.atlas(id);
    }

    /** M8 史料出处：由边上的 sourceRef 换取书目信息。 */
    @GetMapping("/source/{textId}")
    public ResponseEntity<SourceDTO> source(@PathVariable long textId) {
        return service.source(textId)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /** 科举同年：同榜进士是政治派系形成的核心机制，库中原无此类边，由入仕记录生成。 */
    /** 社群画像：Louvain 只给数字 ID，这里补上代表人物、年代、地域、身份，让人认得出是什么群体。 */
    @GetMapping("/community/{cid}")
    public ResponseEntity<CommunityDTO> community(@PathVariable long cid) {
        return service.community(cid)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @GetMapping("/cohort/{id}")
    public List<CohortDTO> cohorts(@PathVariable long id) {
        return service.cohorts(id);
    }

    /** 年号纪年：史料里写的是「元丰三年」而非「1080」。同年可能跨多个政权。 */
    @GetMapping("/nianhao")
    public List<NianHaoDTO> nianhao(@RequestParam(required = false, defaultValue = "-1") int year) {
        return service.nianhao(year);
    }

    /** 政区层级：某地及其下辖地的人物总数。 */
    @GetMapping("/place/{addrId}")
    public ResponseEntity<java.util.Map<String, Object>> place(@PathVariable long addrId) {
        return service.placeTree(addrId)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /** 群体网络：按身份 / 郡望 / 朝代取一批人，只看他们彼此之间的交往。 */
    @GetMapping("/group")
    public GraphDTO group(@RequestParam(required = false) String status,
                          @RequestParam(required = false) String choronym,
                          @RequestParam(required = false) String dynasty,
                          @RequestParam(required = false) Integer limit) {
        return service.group(status, choronym, dynasty, limit);
    }

    @GetMapping("/place/search")
    public List<java.util.Map<String, Object>> searchPlaces(@RequestParam String q) {
        return service.searchPlaces(q);
    }

    @GetMapping("/group/options")
    public java.util.Map<String, List<java.util.Map<String, Object>>> groupOptions() {
        return service.groupOptions();
    }

    @GetMapping("/health")
    public String health() {
        return "ok";
    }
}
