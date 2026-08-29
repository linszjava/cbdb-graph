package cbdb.graph.dto;

import java.util.List;

public record SearchHit(
        long id,
        String nameChn,
        String name,
        String dynasty,
        Integer indexYear,
        Integer birthYear,
        Integer deathYear,
        /** 命中的字号别名 —— 用户搜「东坡」时得让他知道为什么出的是苏轼 */
        List<String> altLabels,
        double score
) {}
