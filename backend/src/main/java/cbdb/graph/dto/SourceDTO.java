package cbdb.graph.dto;

/** M8 史料出处。 */
public record SourceDTO(
        long textId,
        String titleChn,
        String title,
        Integer textYear
) {}
