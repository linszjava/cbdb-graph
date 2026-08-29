package cbdb.graph.dto;

/** 图中的一个人物节点。库中只存简体。 */
public record NodeDTO(
        long id,
        String label,
        String dynasty,
        Integer year,
        Integer birthYear,
        Integer deathYear,
        Boolean female,
        Integer community,
        boolean isCenter,
        Integer generation
) {}
