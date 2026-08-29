package cbdb.graph.dto;

/** 一条关系。sourceRef 指向 Text 节点，配合 pages 即可回溯到史籍页码（M8）。 */
public record EdgeDTO(
        String id,
        long source,
        long target,
        String type,
        String label,
        Integer year,
        Long sourceRef,
        String pages,
        /** 具体篇目（如「跋东坡西山诗 / 攻愧集」）—— 同一对人的同类关系靠它区分 */
        String textTitle,
        Integer upstep,
        Integer dwnstep,
        Integer marstep
) {}
