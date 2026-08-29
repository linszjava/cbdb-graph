package cbdb.graph.dto;

import java.util.List;

/**
 * 所有返回子图的接口共用的数据契约。
 * truncated / totalAvailable 不可省 —— 前端必须能告诉用户「这里还有更多，只是没画出来」。
 */
public record GraphDTO(
        List<NodeDTO> nodes,
        List<EdgeDTO> edges,
        boolean truncated,
        long totalAvailable
) {
    public static GraphDTO empty() {
        return new GraphDTO(List.of(), List.of(), false, 0);
    }
}
