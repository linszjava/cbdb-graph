package cbdb.graph.dto;

/** M5 宦游地图上的一个落点。kind 区分任职地与居址。 */
public record PlaceDTO(
        long id,
        String name,
        double x,
        double y,
        String kind,
        String subtype,
        String office,
        Integer firstYear,
        Integer lastYear
) {}
