package cbdb.graph.dto;

import java.util.List;
import java.util.Map;

/**
 * 社群画像。Louvain 只给数字 ID，看到一堆人认不出是什么群体，
 * 所以从数据里刻画出特征：代表人物、活跃年代、地域、主要身份。
 * 不做「道学集团」这类史学命名 —— 那是判断，不是数据能给的。
 */
public record CommunityDTO(
        long communityId,
        int size,
        /** 代表人物拼成的标识，如「刘禹锡·韩愈·孟郊」 */
        String label,
        String dynasty,
        Integer eraFrom,
        Integer eraTo,
        Integer eraMedian,
        List<Map<String, Object>> topMembers,
        List<Map<String, Object>> topStatuses,
        List<Map<String, Object>> topPlaces
) {}
