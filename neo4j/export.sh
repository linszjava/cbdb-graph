#!/bin/bash
# CBDB SQLite -> neo4j-admin import CSV
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# 默认取 latest/ 下最新的一份 CBDB 快照
DB="${1:-$(ls -t "$ROOT"/latest/*.sqlite3 2>/dev/null | head -1)}"
OUT="${2:-$ROOT/neo4j/csv}"
[ -n "$DB" ] && [ -f "$DB" ] || { echo "找不到 CBDB 快照，请把 .sqlite3 放到 latest/ 下"; exit 1; }
mkdir -p "$OUT"
q() { sqlite3 -csv -noheader "$DB" "$1"; }

# 通用文本清洗：剥掉换行、回车、制表符（neo4j-admin 默认拒绝跨行字段）
cl() { printf "replace(replace(replace(COALESCE(%s,''),char(10),' '),char(13),' '),char(9),' ')" "$1"; }

# 清洗宏：去换行/回车，避免 CSV 多行字段
CL="replace(replace(COALESCE(%s,''),char(10),' '),char(13),' ')"

echo "=== 节点 ==="

echo 'personId:ID(Person),name,nameChn,surnameChn,mingziChn,female:boolean,birthYear:int,deathYear:int,indexYear:int,dynasty,dynastyChn,dynStart:int,dynEnd:int,altNames:string[],altLabels:string[],statuses:string[],choronym,notes,:LABEL' > "$OUT/nodes_person.csv"
q "SELECT b.c_personid, $(cl b.c_name), $(cl b.c_name_chn),
     $(cl b.c_surname_chn), $(cl b.c_mingzi_chn),
     CASE WHEN b.c_female=1 THEN 'true' ELSE 'false' END,
     CASE WHEN COALESCE(b.c_birthyear,0) IN (0,-9999) THEN '' ELSE b.c_birthyear END,
     CASE WHEN COALESCE(b.c_deathyear,0) IN (0,-9999) THEN '' ELSE b.c_deathyear END,
     CASE WHEN COALESCE(b.c_index_year,0) IN (0,-9999) THEN '' ELSE b.c_index_year END,
     $(cl d.c_dynasty), $(cl d.c_dynasty_chn),
     COALESCE(d.c_start,''), COALESCE(d.c_end,''),
     $(cl an.alts), $(cl an.labels), $(cl st.sts),
     $(cl ch.c_choronym_chn),
     $(cl b.c_notes),
     'Person'
   FROM BIOG_MAIN b
   LEFT JOIN DYNASTIES d ON b.c_dy = d.c_dy
   -- 字号别名：20.8 万条，不接进来则搜「东坡」「子瞻」找不到苏轼
   LEFT JOIN (
     SELECT c_personid,
            group_concat(nm, ';')  AS alts,
            group_concat(lbl, ';') AS labels
     FROM (SELECT DISTINCT a.c_personid AS c_personid,
                  replace(a.c_alt_name_chn, ';', '') AS nm,
                  replace(COALESCE(t.c_name_type_desc_chn,'别名') || '：' || a.c_alt_name_chn, ';', '') AS lbl
           FROM ALTNAME_DATA a
           LEFT JOIN ALTNAME_CODES t ON a.c_alt_name_type_code = t.c_name_type_code
           WHERE a.c_alt_name_chn IS NOT NULL AND a.c_alt_name_chn <> '')
     GROUP BY c_personid
   ) an ON b.c_personid = an.c_personid
   -- 社会身份：诗人、画家、僧人、孝子…
   LEFT JOIN (
     SELECT c_personid, group_concat(status, ';') AS sts
     FROM (SELECT DISTINCT d.c_personid AS c_personid,
                  replace(s.c_status_desc_chn, ';', '') AS status
           FROM STATUS_DATA d JOIN STATUS_CODES s ON d.c_status_code = s.c_status_code
           WHERE s.c_status_desc_chn IS NOT NULL AND s.c_status_desc_chn <> '')
     GROUP BY c_personid
   ) st ON b.c_personid = st.c_personid
   -- 郡望：太原王氏、陇西李氏之类，中古士族研究的基本单位
   LEFT JOIN CHORONYM_CODES ch
          ON b.c_choronym_code = ch.c_choronym_code AND ch.c_choronym_chn <> '【未詳】'
   WHERE b.c_personid > 0;" >> "$OUT/nodes_person.csv"

echo 'addrId:ID(Addr),nameChn,name,firstYear:int,lastYear:int,x:double,y:double,chgisId,:LABEL' > "$OUT/nodes_addr.csv"
q "SELECT c_addr_id, $(cl c_name_chn), $(cl c_name),
     CASE WHEN COALESCE(c_firstyear,0)=0 THEN '' ELSE c_firstyear END,
     CASE WHEN COALESCE(c_lastyear,0)=0 THEN '' ELSE c_lastyear END,
     CASE WHEN COALESCE(x_coord,0)=0 THEN '' ELSE x_coord END,
     CASE WHEN COALESCE(y_coord,0)=0 THEN '' ELSE y_coord END,
     $(cl CHGIS_PT_ID), 'Place'
   FROM ADDR_CODES WHERE c_addr_id > 0;" >> "$OUT/nodes_addr.csv"

echo 'officeId:ID(Office),officeChn,officePinyin,officeTrans,:LABEL' > "$OUT/nodes_office.csv"
q "SELECT c_office_id, $(cl c_office_chn), $(cl c_office_pinyin),
     $(cl c_office_trans), 'Office'
   FROM OFFICE_CODES WHERE c_office_id > 0;" >> "$OUT/nodes_office.csv"

echo 'textId:ID(Text),titleChn,title,textYear:int,:LABEL' > "$OUT/nodes_text.csv"
q "SELECT c_textid, $(cl c_title_chn), $(cl c_title),
     CASE WHEN COALESCE(c_text_year,0) IN (0,-9999) THEN '' ELSE c_text_year END, 'Text'
   FROM TEXT_CODES WHERE c_textid > 0;" >> "$OUT/nodes_text.csv"

echo 'entryId:ID(Entry),descChn,desc,:LABEL' > "$OUT/nodes_entry.csv"
q "SELECT c_entry_code, $(cl c_entry_desc_chn), $(cl c_entry_desc), 'EntryType'
   FROM ENTRY_CODES WHERE c_entry_code > 0;" >> "$OUT/nodes_entry.csv"

echo "=== 关系 ==="

# 亲属：保留全部有向边（父->子 与 子->父 各自成边，语义不同）
echo ':START_ID(Person),:END_ID(Person),relChn,rel,kinCode:int,upstep:int,dwnstep:int,marstep:int,colstep:int,source:int,pages,:TYPE' > "$OUT/rels_kin.csv"
q "SELECT k.c_personid, k.c_kin_id, $(cl c.c_kinrel_chn), $(cl c.c_kinrel),
     k.c_kin_code, COALESCE(c.c_upstep,0), COALESCE(c.c_dwnstep,0),
     COALESCE(c.c_marstep,0), COALESCE(c.c_colstep,0),
     COALESCE(k.c_source,''), $(cl k.c_pages), 'KIN'
   FROM KIN_DATA k JOIN KINSHIP_CODES c ON k.c_kin_code=c.c_kincode
   WHERE k.c_personid > 0 AND k.c_kin_id > 0;" >> "$OUT/rels_kin.csv"

# 社会关系：按 c_assoc_pair 去重互反边
echo ':START_ID(Person),:END_ID(Person),relChn,rel,assocCode:int,year:int,textTitle,source:int,pages,:TYPE' > "$OUT/rels_assoc.csv"
q "SELECT a.c_personid, a.c_assoc_id, $(cl c.c_assoc_desc_chn), $(cl c.c_assoc_desc),
     a.c_assoc_code,
     CASE WHEN COALESCE(a.c_assoc_first_year,0) <= 0 THEN '' ELSE a.c_assoc_first_year END,
     $(cl "NULLIF(a.c_text_title,'[n/a]')"),
     COALESCE(a.c_source,''), $(cl a.c_pages), 'ASSOC'
   FROM ASSOC_DATA a JOIN ASSOC_CODES c ON a.c_assoc_code=c.c_assoc_code
   WHERE a.c_personid > 0 AND a.c_assoc_id > 0
     AND (COALESCE(c.c_assoc_pair,0)=0
          OR a.c_assoc_code < c.c_assoc_pair
          OR (a.c_assoc_code = c.c_assoc_pair AND a.c_personid < a.c_assoc_id));" >> "$OUT/rels_assoc.csv"

# 籍贯 / 居址
echo ':START_ID(Person),:END_ID(Addr),typeChn,type,firstYear:int,lastYear:int,source:int,pages,:TYPE' > "$OUT/rels_addr.csv"
q "SELECT d.c_personid, d.c_addr_id, $(cl t.c_addr_desc_chn), $(cl t.c_addr_desc),
     CASE WHEN COALESCE(d.c_firstyear,0) <= 0 THEN '' ELSE d.c_firstyear END,
     CASE WHEN COALESCE(d.c_lastyear,0) <= 0 THEN '' ELSE d.c_lastyear END,
     COALESCE(d.c_source,''), $(cl d.c_pages), 'LIVED_IN'
   FROM BIOG_ADDR_DATA d
   JOIN BIOG_ADDR_CODES t ON d.c_addr_type=t.c_addr_type
   JOIN ADDR_CODES a ON d.c_addr_id=a.c_addr_id
   WHERE d.c_personid > 0 AND d.c_addr_id > 0;" >> "$OUT/rels_addr.csv"

# 任官
echo ':START_ID(Person),:END_ID(Office),firstYear:int,lastYear:int,postingId:int,source:int,pages,:TYPE' > "$OUT/rels_office.csv"
q "SELECT p.c_personid, p.c_office_id,
     CASE WHEN COALESCE(p.c_firstyear,0) <= 0 THEN '' ELSE p.c_firstyear END,
     CASE WHEN COALESCE(p.c_lastyear,0) <= 0 THEN '' ELSE p.c_lastyear END,
     COALESCE(p.c_posting_id,''), COALESCE(p.c_source,''), $(cl p.c_pages), 'HELD_OFFICE'
   FROM POSTED_TO_OFFICE_DATA p JOIN OFFICE_CODES o ON p.c_office_id=o.c_office_id
   WHERE p.c_personid > 0 AND p.c_office_id > 0;" >> "$OUT/rels_office.csv"

# 任职地（宦游）—— 年份来自 POSTED_TO_OFFICE_DATA，经 c_posting_id 关联
echo ':START_ID(Person),:END_ID(Addr),officeId:int,firstYear:int,lastYear:int,postingId:int,:TYPE' > "$OUT/rels_posted.csv"
q "SELECT pa.c_personid, pa.c_addr_id, COALESCE(pa.c_office_id,''),
     CASE WHEN COALESCE(po.c_firstyear,0) <= 0 THEN '' ELSE po.c_firstyear END,
     CASE WHEN COALESCE(po.c_lastyear,0) <= 0 THEN '' ELSE po.c_lastyear END,
     COALESCE(pa.c_posting_id,''), 'POSTED_AT'
   FROM POSTED_TO_ADDR_DATA pa
   JOIN ADDR_CODES a ON pa.c_addr_id=a.c_addr_id
   LEFT JOIN POSTED_TO_OFFICE_DATA po ON pa.c_posting_id=po.c_posting_id
   WHERE pa.c_personid > 0 AND pa.c_addr_id > 0;" >> "$OUT/rels_posted.csv"

# 著述
echo ':START_ID(Person),:END_ID(Text),roleChn,role,year:int,:TYPE' > "$OUT/rels_text.csv"
q "SELECT t.c_personid, t.c_textid, $(cl r.c_role_desc_chn), $(cl r.c_role_desc),
     CASE WHEN COALESCE(t.c_year,0)=0 THEN '' ELSE t.c_year END, 'AUTHORED'
   FROM BIOG_TEXT_DATA t
   LEFT JOIN TEXT_ROLE_CODES r ON t.c_role_id=r.c_role_id
   JOIN TEXT_CODES tc ON t.c_textid=tc.c_textid
   WHERE t.c_personid > 0 AND t.c_textid > 0;" >> "$OUT/rels_text.csv"

# 入仕
echo ':START_ID(Person),:END_ID(Entry),year:int,age:int,rank,:TYPE' > "$OUT/rels_entry.csv"
q "SELECT e.c_personid, e.c_entry_code,
     CASE WHEN COALESCE(e.c_year,0) IN (0,-9999) THEN '' ELSE e.c_year END,
     CASE WHEN COALESCE(e.c_age,0)=0 THEN '' ELSE e.c_age END,
     $(cl e.c_exam_rank), 'ENTERED_VIA'
   FROM ENTRY_DATA e JOIN ENTRY_CODES c ON e.c_entry_code=c.c_entry_code
   WHERE e.c_personid > 0 AND e.c_entry_code > 0;" >> "$OUT/rels_entry.csv"

echo 'nianhaoId:ID(NianHao),nameChn,pinyin,dynastyChn,firstYear:int,lastYear:int,:LABEL' > "$OUT/nodes_nianhao.csv"
q "SELECT c_nianhao_id, $(cl c_nianhao_chn), COALESCE(c_nianhao_pin,''),
     $(cl c_dynasty_chn), c_firstyear, c_lastyear, 'NianHao'
   FROM NIAN_HAO WHERE c_firstyear > 0;" >> "$OUT/nodes_nianhao.csv"

# 科举同年：建榜节点而非人-人边。全库同年对数达 1522 万，
# 直接建人-人边会比整个图现有的 240 万边还多 6 倍；榜节点只需 88,509 条边。
echo 'cohortId:ID(Cohort),year:int,entryChn,size:int,:LABEL' > "$OUT/nodes_cohort.csv"
q "SELECT e.c_year * 100000 + e.c_entry_code,
     e.c_year, $(cl c.c_entry_desc_chn), count(*), 'ExamCohort'
   FROM ENTRY_DATA e
   JOIN ENTRY_CODES c ON e.c_entry_code = c.c_entry_code
   JOIN ENTRY_CODE_TYPE_REL r ON e.c_entry_code = r.c_entry_code
   WHERE e.c_year > 0 AND e.c_personid > 0
     AND (r.c_entry_type LIKE '04%' OR r.c_entry_type LIKE '05%')
   GROUP BY e.c_year, e.c_entry_code
   HAVING count(*) > 1;" >> "$OUT/nodes_cohort.csv"

echo ':START_ID(Person),:END_ID(Cohort),rank,:TYPE' > "$OUT/rels_cohort.csv"
q "SELECT e.c_personid, e.c_year * 100000 + e.c_entry_code,
     $(cl e.c_exam_rank), 'SAME_COHORT'
   FROM ENTRY_DATA e
   JOIN ENTRY_CODE_TYPE_REL r ON e.c_entry_code = r.c_entry_code
   WHERE e.c_year > 0 AND e.c_personid > 0
     AND (r.c_entry_type LIKE '04%' OR r.c_entry_type LIKE '05%')
     AND EXISTS (SELECT 1 FROM ENTRY_DATA x
                 WHERE x.c_year = e.c_year AND x.c_entry_code = e.c_entry_code
                   AND x.c_personid > 0 AND x.c_personid <> e.c_personid);" >> "$OUT/rels_cohort.csv"

# 政区隶属：县属州、州属路，支持「福建路所有人物」这类查询
echo ':START_ID(Addr),:END_ID(Addr),firstYear:int,lastYear:int,:TYPE' > "$OUT/rels_place_belongs.csv"
q "SELECT b.c_addr_id, b.c_belongs_to,
     CASE WHEN COALESCE(b.c_firstyear,0) <= 0 THEN '' ELSE b.c_firstyear END,
     CASE WHEN COALESCE(b.c_lastyear,0) <= 0 THEN '' ELSE b.c_lastyear END,
     'BELONGS_TO'
   FROM ADDR_BELONGS_DATA b
   JOIN ADDR_CODES a1 ON b.c_addr_id = a1.c_addr_id
   JOIN ADDR_CODES a2 ON b.c_belongs_to = a2.c_addr_id
   WHERE b.c_addr_id > 0 AND b.c_belongs_to > 0;" >> "$OUT/rels_place_belongs.csv"

echo "=== 完成 ==="
wc -l "$OUT"/*.csv
