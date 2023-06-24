-- # Challenge DAVID COSTA
-- DISCLAIMER: I had to decrease by 87.5% the amount of records to insert due to user quota issues
--             ORA-01536 avoidance: It was made a request via Oracle Apex to increase storage space.
-- select bytes,max_bytes, max_bytes-bytes dif_free from user_ts_quotas;
-- COMMITS IN 'my' APEX ARE AUTOMATIC


-- 0
CREATE TABLE item(
    item          VARCHAR2(25) NOT NULL,
    dept          NUMBER(4)    NOT NULL,
    item_desc     VARCHAR2(25) NOT NULL
)
/
CREATE TABLE loc(
    loc           NUMBER(10)   NOT NULL,
    loc_desc      VARCHAR2(25) NOT NULL
)
/
CREATE TABLE item_loc_soh(
    item          VARCHAR2(25) NOT NULL,
    loc           NUMBER(10)   NOT NULL,
    dept          NUMBER(4)    NOT NULL,
    unit_cost     NUMBER(20,4) NOT NULL,
    stock_on_hand NUMBER(12,4) NOT NULL
)
/
--- in average this will take 1s to be executed
INSERT INTO item(item,dept,item_desc)
SELECT level, ROUND(DBMS_RANDOM.VALUE(1,100)), TRANSLATE(dbms_random.string('a', 20), 'abcXYZ', level) FROM dual CONNECT BY LEVEL <= 10000
/
--- in average this will take 1s to be executed
INSERT INTO  loc(loc,loc_desc)
SELECT level+100, TRANSLATE(dbms_random.string('a', 20), 'abcXYZ', level) FROM dual CONNECT BY LEVEL <= 1000
/
-- in average this will take less than 120s to be executed
INSERT INTO  item_loc_soh (item, loc, dept, unit_cost, stock_on_hand)
SELECT item, loc, dept, (DBMS_RANDOM.VALUE(5000,50000)), ROUND(DBMS_RANDOM.VALUE(1000,100000))
FROM item, loc
/
-- INSERT INTO item(item,dept,item_desc)
-- SELECT level, ROUND(DBMS_RANDOM.VALUE(1,100)), TRANSLATE(dbms_random.string('a', 20), 'abcXYZ', level) FROM dual CONNECT BY LEVEL <= 1250
-- /
-- --- in average this will take 1s to be executed
-- INSERT INTO  loc(loc,loc_desc)
-- SELECT level+100, TRANSLATE(dbms_random.string('a', 20), 'abcXYZ', level) FROM dual CONNECT BY LEVEL <= 125
-- /
-- -- in average this will take less than 120s to be executed
-- INSERT INTO  item_loc_soh (item, loc, dept, unit_cost, stock_on_hand)
-- SELECT item, loc, dept, (DBMS_RANDOM.VALUE(5000,50000)), ROUND(DBMS_RANDOM.VALUE(1000,100000))
-- FROM item, loc
-- /

-- ## Must Have
-- ### Data Model
-- 1)
-- The PKs implicitly create indexes and guarantee data integrity
ALTER TABLE item ADD CONSTRAINT item_pk PRIMARY KEY (item)
/
ALTER TABLE loc ADD CONSTRAINT loc_pk PRIMARY KEY (loc)
/
-- 
-- FKs to enhance data integrity
ALTER TABLE item_loc_soh ADD CONSTRAINT item_fk FOREIGN KEY(item) REFERENCES item(item)
/
ALTER TABLE item_loc_soh ADD CONSTRAINT loc_fk FOREIGN KEY(loc) REFERENCES loc(loc)
/
--
-- As one of the attributes that most store/warehouse users search is by dept, indexes on dept were created
CREATE INDEX item_dept_idx ON item(dept)
/
CREATE INDEX item_loc_soh_dept_idx ON item_loc_soh(dept)
/

--2) Easier to write and more suitable for limited quota space
ALTER TABLE item MODIFY
    PARTITION BY HASH(dept)
    PARTITIONS 100
/
ALTER TABLE item_loc_soh MODIFY
    PARTITION BY HASH(loc)
    PARTITIONS 125
/

--3) The idea here is to limit the free space available for updates, so less suspicious to row contention
ALTER TABLE item PCTFREE 1
/
ALTER TABLE loc PCTFREE 1
/
ALTER TABLE item_loc_soh PCTFREE 1
/
-- 4)
-- Already on script StockApplication.sql
-- Procedures: wwv_flow_imp_page.create_worksheet_column
--             create_page_item              
-- 5)
BEGIN
    EXECUTE IMMEDIATE 'CREATE TABLE Dept AS SELECT dept dept, item_desc dept_desc from item where 1=0';
    EXECUTE IMMEDIATE 'ALTER TABLE Dept PCTFREE 1';
    EXECUTE IMMEDIATE 'ALTER TABLE dept ADD CONSTRAINT dept_pk PRIMARY KEY(dept)';
END;
/
DECLARE                         
    TYPE t_dept IS TABLE OF item.dept%TYPE;
    l_dept_tab t_dept := t_dept();   
BEGIN
    
    SELECT dept
    BULK COLLECT 
    INTO  l_dept_tab
    FROM item
    GROUP BY dept;

    FORALL i in l_dept_tab.first .. l_dept_tab.last
        INSERT INTO Dept(dept,dept_desc) VALUES (l_dept_tab(i),dbms_random.string('a', 20));
END;
/
BEGIN
    EXECUTE IMMEDIATE 'ALTER TABLE item ADD CONSTRAINT item_dept_fk FOREIGN KEY(dept) REFERENCES dept(dept)';
    EXECUTE IMMEDIATE 'ALTER TABLE item_loc_soh ADD CONSTRAINT item_loc_dept_fk FOREIGN KEY(dept) REFERENCES dept(dept)';
END;
/


-- ### Data Model
-- 6) The new table for this feature
CREATE TABLE item_loc_soh_hist AS SELECT * FROM item_loc_soh WHERE 1=0
/
ALTER TABLE item_loc_soh_hist ADD stock_val number(30,4) not null
/
CREATE OR REPLACE PACKAGE p_hist
IS
   PROCEDURE ins_hist(p_loc_ini IN loc.LOC%TYPE
                     ,p_loc_fin IN loc.LOC%TYPE DEFAULT NULL);
END;
/
CREATE OR REPLACE PACKAGE BODY p_hist
IS
  PROCEDURE ins_hist(p_loc_ini IN loc.LOC%TYPE
                    ,p_loc_fin IN loc.LOC%TYPE DEFAULT NULL)
  IS
    TYPE tt_hist IS TABLE OF item_loc_soh%ROWTYPE;  
      t_hist tt_hist := tt_hist(); 
    BEGIN
     SELECT *
     BULK COLLECT
     INTO
     t_hist
     FROM item_loc_soh
     where loc between p_loc_ini and NVL(p_loc_fin,p_loc_ini);

     FORALL i in t_hist.first .. t_hist.last
        INSERT INTO item_loc_soh_hist(item
                                     ,loc
                                     ,dept
                                     ,unit_cost
                                     ,stock_on_hand
                                     ,stock_val) 
                            VALUES (t_hist(i).item
                                   ,t_hist(i).loc
                                   ,t_hist(i).dept
                                   ,t_hist(i).unit_cost
                                   ,t_hist(i).stock_on_hand
                                   ,t_hist(i).unit_cost*t_hist(i).stock_on_hand);
    END;   
END;
/
BEGIN
    p_hist.ins_hist(108);
END;
/

-- 7) Already on script StockApplication.sql
-- wwv_flow_imp_page.create_worksheet_column(
 -- p_id=>wwv_flow_imp.id(8192599974479513)
-- ,p_db_column_name=>'DEPT'
-- ,p_display_order=>30
-- ,p_column_identifier=>'C'
-- ,p_column_label=>'Dept.'
-- ,p_column_type=>'NUMBER'
-- ,p_heading_alignment=>'RIGHT'
-- ,p_column_alignment=>'RIGHT'
-- ,p_use_as_row_header=>'N'
-- );

-- 8)
-- Type at schema level - required for pipelined function
CREATE TYPE tt_pipe_loc AS OBJECT (
  loc       NUMBER(10),
  loc_desc  VARCHAR2(25)
)
/
CREATE TYPE t_pipe_loc IS TABLE OF tt_pipe_loc
/
CREATE OR REPLACE FUNCTION getLocPipe 
RETURN t_pipe_loc PIPELINED 
IS
  TYPE l_tt_hist IS TABLE OF loc%ROWTYPE;  
   l_t_hist l_tt_hist := l_tt_hist(); 
BEGIN
   SELECT *
     BULK COLLECT
     INTO
     l_t_hist
    FROM loc;

  FOR i in l_t_hist.first .. l_t_hist.last
  LOOP
    PIPE ROW(tt_pipe_loc(l_t_hist(i).loc,l_t_hist(i).loc_desc||' ||'));   
  END LOOP;
  
  RETURN;
END;
/
-- Function invoked between the lines 17671 and 17689 at script StockApplication.sql
-- wwv_flow_imp_page.create_page_item(
 -- p_id=>wwv_flow_imp.id(8192058268479508)
-- ,p_name=>'P1_LOC'
-- ,p_item_sequence=>10
-- ,p_prompt=>'Loc - DTC'
-- ,p_display_as=>'NATIVE_POPUP_LOV'
-- ,p_lov=>'SELECT loc || '' - '' || loc_desc, loc FROM TABLE(getLocPipe)'
-- ,p_lov_display_null=>'YES'
-- ,p_cSize=>30
-- ,p_field_template=>wwv_flow_imp.id(8376771809499255)
-- ,p_item_template_options=>'#DEFAULT#'
-- ,p_lov_display_extra=>'YES'
-- ,p_attribute_01=>'POPUP'
-- ,p_attribute_02=>'FIRST_ROWSET'
-- ,p_attribute_03=>'N'
-- ,p_attribute_04=>'N'
-- ,p_attribute_05=>'N'
-- );
  
--## Should Have
--### Performance

-- 9) TABLE ACCESS FULL Solved with index:
CREATE INDEX item_loc_soh_dept_loc_idx ON item_loc_soh(loc, dept)
/
--SELECT *   
--FROM TABLE(dbms_xplan.display('HTMLDB_PLAN_TABLE'));
-- Plan hash value: 4266531040
-- ----------------------------------------------------------------------------------------------------------------------------------------
-- | Id | Operation | Name | Rows | Bytes | Cost (%CPU)| Time | Pstart| Pstop |
-- ----------------------------------------------------------------------------------------------------------------------------------------
-- | 0 | SELECT STATEMENT | | 13 | 247 | 9 (0)| 00:00:01 | | |
-- | 1 | TABLE ACCESS BY GLOBAL INDEX ROWID BATCHED| ITEM_LOC_SOH | 13 | 247 | 9 (0)| 00:00:01 | 5 | 5 |
-- |* 2 | INDEX RANGE SCAN | ITEM_LOC_SOH_DEPT_LOC_IDX | 2 | | 3 (0)| 00:00:01 | | |
-- ----------------------------------------------------------------------------------------------------------------------------------------
-- Predicate Information (identified by operation id):
-- ---------------------------------------------------
-- 2 - access("LOC"=172 AND "DEPT"=38)

-- 10) I am going to use the DBMS_PARALLEL_EXECUTE package (truncate table due to APEX quota issues)
DECLARE
  l_sql_trunc VARCHAR2(1000);
  l_chunk_sql VARCHAR2(1000);
  l_sql_stmt  VARCHAR2(1000);  
  l_try       NUMBER;
  l_status    NUMBER;
BEGIN
  l_try    := 0;
  l_status := 0;
  
  l_sql_trunc:= 'truncate table ITEM_LOC_SOH_HIST';
  EXECUTE IMMEDIATE l_sql_trunc;
  
  DBMS_PARALLEL_EXECUTE.create_task (task_name => 'TASK_DTC');
  l_chunk_sql := 'SELECT loc, loc FROM loc';

  DBMS_PARALLEL_EXECUTE.CREATE_CHUNKS_BY_SQL('TASK_DTC'
                                            , l_chunk_sql
                                            , false);
  
  l_sql_stmt := 'BEGIN P_HIST.ins_hist(:start_id,:end_id); END;';
  
  DBMS_PARALLEL_EXECUTE.RUN_TASK('TASK_DTC'
                                , l_sql_stmt
                                , DBMS_SQL.NATIVE
                                , parallel_level => 5);
                                
  l_status := DBMS_PARALLEL_EXECUTE.TASK_STATUS('TASK_DTC');
  WHILE(l_try < 2 AND l_status != DBMS_PARALLEL_EXECUTE.FINISHED) 
  LOOP
    L_try := l_try + 1;
    DBMS_PARALLEL_EXECUTE.RESUME_TASK('TASK_DTC');
    L_status := DBMS_PARALLEL_EXECUTE.TASK_STATUS('TASK_DTC');
  END LOOP;

  DBMS_PARALLEL_EXECUTE.drop_task (task_name => 'TASK_DTC');
END;
/

-- 11)
-- After checking AWR report (AWR.html), there is an issue
-- at the Scheduler (Wait Classes by Total Wait Time) due to the "Total wait" time and "Avg Wait".
-- It is likely there are jobs invoking the statements in the table "Top SQL with Top Events".
-- A potential solution is to solve the TABLE ACCESS - STORAGE FULL with the appropriate INDEX,
-- with a similar way like the one on 9. 

-- 12)
-- 
-- AT DELIVERY DAY
-- NOT Finished due to lack of time and suitable tools
-- Components MISSING:
--                     - program to consume the JSON RestService
--                     - export to CSV file with the appropriate multi-threading method
--SERVER SIDE Done in Apex
--RESTful Data Service 
--
-- ABLE TO FINISH BEFORE FEEDBACK
-- JAR inside EXEC_STOCK_LOC_DTC.zip (requires the "lib" forder due to a JSON library)
-- Files in output.zip
-- JAVA project in STOCK_LOC_DTC.zip