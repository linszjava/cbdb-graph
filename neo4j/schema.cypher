// ---- 约束与索引（导入后执行）----
CREATE CONSTRAINT person_id IF NOT EXISTS FOR (p:Person) REQUIRE p.personId IS UNIQUE;
CREATE CONSTRAINT place_id  IF NOT EXISTS FOR (a:Place)  REQUIRE a.addrId   IS UNIQUE;
CREATE CONSTRAINT office_id IF NOT EXISTS FOR (o:Office) REQUIRE o.officeId IS UNIQUE;
CREATE CONSTRAINT text_id   IF NOT EXISTS FOR (t:Text)   REQUIRE t.textId   IS UNIQUE;

CREATE INDEX person_name_chn IF NOT EXISTS FOR (p:Person) ON (p.nameChn);
CREATE INDEX person_dynasty  IF NOT EXISTS FOR (p:Person) ON (p.dynastyChn);
CREATE INDEX person_idxyear  IF NOT EXISTS FOR (p:Person) ON (p.indexYear);
CREATE INDEX place_name_chn  IF NOT EXISTS FOR (a:Place)  ON (a.nameChn);
CREATE INDEX office_name_chn IF NOT EXISTS FOR (o:Office) ON (o.officeChn);
CREATE INDEX text_title_chn  IF NOT EXISTS FOR (t:Text)   ON (t.titleChn);

// 别名拼成带分隔空格的单串，供精确与前缀匹配。
// 两端补空格，' 子瞻 ' 这样的模式才能匹配到首尾两个别名。
MATCH (p:Person) WHERE p.altNames IS NOT NULL
CALL (p) { SET p.altSearch = reduce(a = ' ', x IN p.altNames | a + x + ' ') }
IN TRANSACTIONS OF 20000 ROWS;

// 不用全文索引：中文按单字切分，搜「东坡」会返回一堆带「坡」字的人，全是噪音。
// 改用 TEXT 索引做精确 / 前缀 / 包含三级匹配。
CREATE TEXT INDEX person_name_text  IF NOT EXISTS FOR (p:Person) ON (p.nameChn);
CREATE TEXT INDEX person_alt_text   IF NOT EXISTS FOR (p:Person) ON (p.altSearch);

CREATE INDEX person_choronym  IF NOT EXISTS FOR (p:Person)     ON (p.choronym);
CREATE INDEX cohort_year      IF NOT EXISTS FOR (c:ExamCohort) ON (c.year);
CREATE INDEX nianhao_span     IF NOT EXISTS FOR (n:NianHao)    ON (n.firstYear, n.lastYear);

// 地点空间索引（用于地图范围查询）
MATCH (a:Place) WHERE a.x IS NOT NULL AND a.location IS NULL
CALL (a) { SET a.location = point({longitude: a.x, latitude: a.y}) }
IN TRANSACTIONS OF 10000 ROWS;
CREATE POINT INDEX place_location IF NOT EXISTS FOR (a:Place) ON (a.location);
