package cbdb.graph.dto;

import java.util.List;

/** 科举同年榜。同年是政治派系形成的核心机制。 */
public record CohortDTO(
        long cohortId,
        Integer year,
        String entryChn,
        int size,
        List<SearchHit> members
) {}
