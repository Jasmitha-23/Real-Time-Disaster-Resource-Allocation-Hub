-- Optional scale seed: run after schema.sql. Commits in batches to limit undo usage.
DECLARE
  v_loc NUMBER; v_res NUMBER; v_batch PLS_INTEGER := 0;
  TYPE types_t IS VARRAY(4) OF VARCHAR2(20);
  types types_t := types_t('MEDICAL','VEHICLE','EQUIPMENT','FOOD_WATER');
BEGIN
  FOR i IN 1..50000 LOOP
    INSERT INTO locations(location_name,latitude,longitude,location_type)
      VALUES('Bulk Depot '||i,ROUND(DBMS_RANDOM.VALUE(8,37),6),ROUND(DBMS_RANDOM.VALUE(68,97),6),'WAREHOUSE')
      RETURNING location_id INTO v_loc;
    FOR j IN 1..2 LOOP
      INSERT INTO resources(resource_name,resource_type,total_qty,available_qty,location_id)
        VALUES('Bulk stock '||i||'-'||j,types(TRUNC(DBMS_RANDOM.VALUE(1,5))),100,TRUNC(DBMS_RANDOM.VALUE(1,101)),v_loc);
    END LOOP;
    v_batch:=v_batch+1;
    IF MOD(v_batch,5000)=0 THEN COMMIT; END IF;
  END LOOP;
  COMMIT;
  DBMS_STATS.GATHER_TABLE_STATS(USER,'LOCATIONS',cascade=>TRUE);
  DBMS_STATS.GATHER_TABLE_STATS(USER,'RESOURCES',cascade=>TRUE);
END;
/

-- Matching cleanup when the benchmark dataset is no longer needed:
-- DELETE FROM resources WHERE location_id IN (SELECT location_id FROM locations WHERE location_name LIKE 'Bulk Depot%');
-- DELETE FROM locations WHERE location_name LIKE 'Bulk Depot%';
-- COMMIT;
