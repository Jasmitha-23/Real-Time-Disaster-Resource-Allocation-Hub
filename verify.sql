-- verify.sql : smoke test for the Disaster Hub database.
-- Run as user HUB in SQL Developer with F5 (Run Script), right AFTER reset.sql + schema.sql.
-- It creates TEST_ rows and fulfils some sample requests, so run reset.sql + schema.sql
-- again before your demo. Output appears in the Script Output / DBMS Output pane.
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
  v_pass PLS_INTEGER := 0; v_fail PLS_INTEGER := 0;
  v_code VARCHAR2(40); v_msg VARCHAR2(400);
  v_n NUMBER; v_rid NUMBER; v_dist NUMBER; v_st VARCHAR2(20);
  r_eq NUMBER; r_med NUMBER; q_high NUMBER; q_low NUMBER; q_exp NUMBER;
  inc_t NUMBER; q_inc NUMBER; q_closed NUMBER;

  PROCEDURE chk(p_name VARCHAR2, p_ok BOOLEAN, p_info VARCHAR2 DEFAULT NULL) IS
  BEGIN
    IF p_ok THEN v_pass := v_pass + 1; DBMS_OUTPUT.PUT_LINE('PASS  ' || p_name);
    ELSE v_fail := v_fail + 1; DBMS_OUTPUT.PUT_LINE('FAIL  ' || p_name || '  -> ' || p_info);
    END IF;
  END;

  -- Runs a statement that MUST fail with the given SQLCODE.
  PROCEDURE expect_err(p_name VARCHAR2, p_sql VARCHAR2, p_sqlcode NUMBER) IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
    ROLLBACK; chk(p_name, FALSE, 'statement succeeded but should have failed');
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK; chk(p_name, SQLCODE = p_sqlcode, 'got ' || SQLERRM);
  END;

  PROCEDURE fulfill(p_req NUMBER, p_user NUMBER, p_ov NUMBER, p_expect VARCHAR2, p_name VARCHAR2) IS
  BEGIN
    sp_fulfill_request(p_request_id => p_req, p_dispatcher_id => p_user, p_override => p_ov,
                       o_code => v_code, o_msg => v_msg);
    chk(p_name, v_code = p_expect, 'expected ' || p_expect || ', got ' || v_code || ': ' || v_msg);
  END;

  -- Separate (autonomous) transaction = a "second dispatcher" inside one session.
  PROCEDURE busy_probe(p_req NUMBER) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    sp_fulfill_request(p_request_id => p_req, p_dispatcher_id => 2, p_override => 0,
                       o_code => v_code, o_msg => v_msg);
    ROLLBACK;
  END;

  PROCEDURE set_status(p_inc NUMBER, p_user NUMBER, p_status VARCHAR2, p_expect VARCHAR2, p_name VARCHAR2) IS
  BEGIN
    sp_set_incident_status(p_incident_id => p_inc, p_user_id => p_user, p_status => p_status,
                           o_code => v_code, o_msg => v_msg);
    chk(p_name, v_code = p_expect, 'expected ' || p_expect || ', got ' || v_code || ': ' || v_msg);
  END;

  PROCEDURE nearest(p_inc NUMBER, p_user NUMBER, p_radius NUMBER, p_expect VARCHAR2, p_name VARCHAR2) IS
  BEGIN
    sp_allocate_nearest(p_incident_id => p_inc, p_resource_type => 'VEHICLE', p_qty => 1,
                        p_requested_by => 1, p_dispatcher_id => p_user, p_radius_km => p_radius,
                        o_code => v_code, o_msg => v_msg, o_resource_id => v_rid, o_distance_km => v_dist);
    chk(p_name, v_code = p_expect, 'expected ' || p_expect || ', got ' || v_code || ': ' || v_msg);
  END;

BEGIN
  DBMS_OUTPUT.PUT_LINE('=== 1. Objects compiled and present ===');
  SELECT COUNT(*) INTO v_n FROM user_objects WHERE status = 'INVALID';
  chk('No INVALID objects', v_n = 0, v_n || ' invalid. Run: SELECT name, line, text FROM user_errors;');
  SELECT COUNT(*) INTO v_n FROM user_objects WHERE object_type = 'PROCEDURE' AND object_name IN
    ('SP_FULFILL_REQUEST','SP_REJECT_REQUEST','SP_PROCESS_QUEUE','SP_ALLOCATE_NEAREST','SP_SET_INCIDENT_STATUS');
  chk('All 5 procedures exist', v_n = 5, 'found ' || v_n);
  SELECT COUNT(*) INTO v_n FROM user_triggers WHERE status = 'ENABLED' AND trigger_name IN
    ('TRG_MED_ISA','TRG_RES_TYPE_GUARD','TRG_ALLOC_IMMUTABLE');
  chk('All 3 triggers exist and are enabled', v_n = 3, 'found ' || v_n);
  SELECT COUNT(*) INTO v_n FROM user_indexes WHERE index_name IN
    ('IDX_LOC_COORDS','IDX_REQ_QUEUE','IDX_RES_LOC','IDX_REQ_RES_STATUS','IDX_REQ_INCIDENT','IDX_ALLOC_BY','IDX_USERS_LOC');
  chk('All 7 named indexes exist', v_n = 7, 'found ' || v_n);
  SELECT COUNT(*) INTO v_n FROM user_ind_columns
   WHERE index_name = 'IDX_LOC_COORDS' AND ((column_position = 1 AND column_name = 'LATITUDE')
                                          OR (column_position = 2 AND column_name = 'LONGITUDE'));
  chk('IDX_LOC_COORDS is composite (latitude, longitude)', v_n = 2, 'columns wrong');

  -- Test data (committed so the autonomous "second dispatcher" can see it)
  INSERT INTO resources (resource_name, resource_type, total_qty, available_qty, location_id)
    VALUES ('TEST_Equipment', 'EQUIPMENT', 10, 10, 1) RETURNING resource_id INTO r_eq;
  INSERT INTO resources (resource_name, resource_type, total_qty, available_qty, location_id)
    VALUES ('TEST_Medicine', 'MEDICAL', 50, 50, 1) RETURNING resource_id INTO r_med;
  INSERT INTO resource_requests (incident_id, resource_id, requested_by, requested_qty, priority_score)
    VALUES (1, r_eq, 1, 8, 120) RETURNING request_id INTO q_high;
  INSERT INTO resource_requests (incident_id, resource_id, requested_by, requested_qty, priority_score)
    VALUES (1, r_eq, 1, 5, 40) RETURNING request_id INTO q_low;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('=== 2. Locking: priority-based wait-die ===');
  SELECT available_qty INTO v_n FROM resources WHERE resource_id = r_eq FOR UPDATE; -- dispatcher A holds the row
  busy_probe(q_low);                                                                -- dispatcher B, low priority
  ROLLBACK;                                                                         -- A releases
  chk('Low-priority request dies (NOWAIT) when stock row is locked', v_code = 'BUSY_RETRY',
      'got ' || v_code || ': ' || v_msg);

  DBMS_OUTPUT.PUT_LINE('=== 3. Priority guard, roles, double-booking ===');
  fulfill(q_low,  2, 0, 'PRIORITY_HOLD', 'Low request held back for higher-priority request');
  fulfill(q_low,  1, 0, 'FORBIDDEN',     'Field responder cannot fulfill');
  fulfill(q_low,  2, 1, 'FORBIDDEN',     'Dispatcher cannot use override');
  fulfill(q_high, 2, 0, 'OK',            'High-priority request fulfilled');
  SELECT available_qty INTO v_n FROM resources WHERE resource_id = r_eq;
  chk('Stock deducted exactly once (10 - 8 = 2)', v_n = 2, 'available_qty = ' || v_n);
  fulfill(q_high, 3, 0, 'ALREADY_DONE',  'Same request cannot be fulfilled twice');
  SELECT COUNT(*) INTO v_n FROM dispatch_allocations WHERE request_id = q_high;
  chk('Exactly one audit row for the request', v_n = 1, 'rows = ' || v_n);
  fulfill(q_low,  3, 1, 'INSUFFICIENT',  'Commander override still cannot exceed stock');

  DBMS_OUTPUT.PUT_LINE('=== 4. Reject ===');
  sp_reject_request(p_request_id => q_low, p_dispatcher_id => 1, o_code => v_code, o_msg => v_msg);
  chk('Field responder cannot reject', v_code = 'FORBIDDEN', 'got ' || v_code);
  sp_reject_request(p_request_id => q_low, p_dispatcher_id => 2, o_code => v_code, o_msg => v_msg);
  chk('Dispatcher rejects pending request', v_code = 'OK', 'got ' || v_code || ': ' || v_msg);
  sp_reject_request(p_request_id => q_low, p_dispatcher_id => 2, o_code => v_code, o_msg => v_msg);
  chk('Cannot reject twice', v_code = 'ALREADY_DONE', 'got ' || v_code);

  DBMS_OUTPUT.PUT_LINE('=== 5. Triggers and constraints ===');
  expect_err('Audit log UPDATE blocked',
    'UPDATE dispatch_allocations SET allocated_qty = allocated_qty WHERE request_id = ' || q_high, -20001);
  expect_err('Audit log DELETE blocked',
    'DELETE FROM dispatch_allocations WHERE request_id = ' || q_high, -20001);
  expect_err('Medical subtype on a non-MEDICAL resource blocked',
    'INSERT INTO medical_supplies VALUES (' || r_eq || ', 0, 20, TRUNC(SYSDATE) + 30)', -20010);
  expect_err('Cold-chain item without temperature blocked',
    'INSERT INTO medical_supplies VALUES (' || r_med || ', 1, NULL, TRUNC(SYSDATE) + 30)', -2290);
  INSERT INTO medical_supplies VALUES (r_med, 0, 20, TRUNC(SYSDATE) - 1);   -- valid but EXPIRED stock
  COMMIT;
  expect_err('Cannot change MEDICAL type while subtype row exists',
    'UPDATE resources SET resource_type = ''EQUIPMENT'' WHERE resource_id = ' || r_med, -20011);

  DBMS_OUTPUT.PUT_LINE('=== 6. Expired stock ===');
  INSERT INTO resource_requests (incident_id, resource_id, requested_by, requested_qty, priority_score)
    VALUES (1, r_med, 1, 1, 50) RETURNING request_id INTO q_exp;
  COMMIT;
  fulfill(q_exp, 2, 0, 'EXPIRED', 'Expired medicine cannot be dispatched');

  DBMS_OUTPUT.PUT_LINE('=== 7. Incident lifecycle ===');
  INSERT INTO disaster_incidents (title, severity_level, location_id)
    VALUES ('TEST_Incident', 2, 5) RETURNING incident_id INTO inc_t;
  INSERT INTO resource_requests (incident_id, resource_id, requested_by, requested_qty, priority_score)
    VALUES (inc_t, r_eq, 1, 1, 30) RETURNING request_id INTO q_inc;
  COMMIT;
  set_status(inc_t, 2, 'CONTAINED', 'FORBIDDEN',          'Only commander changes incident status');
  set_status(inc_t, 3, 'RESOLVED',  'INVALID_TRANSITION', 'ACTIVE -> RESOLVED directly is refused');
  set_status(inc_t, 3, 'CONTAINED', 'OK',                 'ACTIVE -> CONTAINED');
  set_status(inc_t, 3, 'RESOLVED',  'OK',                 'CONTAINED -> RESOLVED');
  SELECT status INTO v_st FROM resource_requests WHERE request_id = q_inc;
  chk('Pending requests auto-rejected on RESOLVED', v_st = 'REJECTED', 'status = ' || v_st);
  INSERT INTO resource_requests (incident_id, resource_id, requested_by, requested_qty, priority_score)
    VALUES (inc_t, r_eq, 1, 1, 30) RETURNING request_id INTO q_closed;   -- forced in directly via SQL
  COMMIT;
  fulfill(q_closed, 2, 0, 'INCIDENT_CLOSED', 'Cannot fulfill for a RESOLVED incident');

  DBMS_OUTPUT.PUT_LINE('=== 8. Nearest allocation (spatial search + lock) ===');
  nearest(1, 2, 500, 'OK', 'Allocate nearest VEHICLE to Khammam within 500 km');
  chk('Nearest returns resource and distance', v_rid IS NOT NULL AND v_dist > 0,
      'resource=' || v_rid || ', distance=' || v_dist);
  DBMS_OUTPUT.PUT_LINE('      chose resource ' || v_rid || ' at ' || v_dist || ' km');
  nearest(1, 2, 1,   'NONE_AVAILABLE',  'Nothing within 1 km');
  nearest(1, 1, 500, 'FORBIDDEN',       'Field responder cannot allocate');
  nearest(inc_t, 2, 500, 'INCIDENT_CLOSED', 'Cannot allocate to a RESOLVED incident');

  DBMS_OUTPUT.PUT_LINE('=== RESULT: ' || v_pass || ' passed, ' || v_fail || ' failed ===');
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  DBMS_OUTPUT.PUT_LINE('ABORTED: ' || SQLERRM);
  DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
  DBMS_OUTPUT.PUT_LINE('So far: ' || v_pass || ' passed, ' || v_fail || ' failed');
END;
/

-- Separate block: if sp_process_queue's parameter names differ, only this block fails (PLS-00306).
DECLARE
  v_n NUMBER; v_s VARCHAR2(4000); v_c VARCHAR2(40);
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== 9. Process queue ===');
  sp_process_queue(p_dispatcher_id => 1, o_processed => v_n, o_summary => v_s, o_code => v_c);
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_c = 'FORBIDDEN' THEN 'PASS  ' ELSE 'FAIL  ' END
                       || 'Field responder cannot process queue (got ' || v_c || ')');
  sp_process_queue(p_dispatcher_id => 2, o_processed => v_n, o_summary => v_s, o_code => v_c);
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_c = 'OK' THEN 'PASS  ' ELSE 'FAIL  ' END
                       || 'Dispatcher processes queue: ' || v_n || ' fulfilled; ' || v_s);
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('ABORTED queue test: ' || SQLERRM);
END;
/
