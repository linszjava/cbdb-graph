package cbdb.graph.dto;

import java.util.List;
import java.util.Map;

public record PersonDTO(
        long id,
        String nameChn,
        String name,
        String surnameChn,
        String dynasty,
        Integer birthYear,
        Integer deathYear,
        Integer indexYear,
        Boolean female,
        String notes,
        /** 「字：子瞻」「谥号：文忠」这类带类型的别名 */
        List<String> altLabels,
        /** 诗人、画家、僧人、入元祐党籍者… */
        List<String> statuses,
        /** 郡望，如赵郡、太原 */
        String choronym,
        long assocDegree,
        long kinDegree,
        Integer community,
        Double betweenness,
        Double pagerank,
        List<Map<String, Object>> addresses,
        List<Map<String, Object>> offices,
        List<Map<String, Object>> entries,
        List<Map<String, Object>> texts
) {}
