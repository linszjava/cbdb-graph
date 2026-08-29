package cbdb.graph.dto;

/** 年号纪年。史料里用的是「元丰三年」，不是「1080」。 */
public record NianHaoDTO(
        String nameChn,
        String dynastyChn,
        int firstYear,
        int lastYear,
        int nth,
        String label
) {}
