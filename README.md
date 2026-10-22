# Real-Time Disaster Resource Allocation Hub

Oracle SQL + Express + Node + React 18/htm CDN. Oracle XE 21c or 23ai Free is supported with `node-oracledb` 6 Thin mode. The browser app has no build step.

## Setup

1. As SYSTEM on `XEPDB1` (XE) or `FREEPDB1` (23ai Free), create the app user and grant quota:
   `CREATE USER hub IDENTIFIED BY hub123 DEFAULT TABLESPACE users QUOTA UNLIMITED ON users;`
   `GRANT CONNECT, RESOURCE TO hub;`
2. Connect as `hub` and run `schema.sql` with SQL Developer F5.
3. Optional scale dataset: run `seed_bulk.sql` after the schema; it adds 50,000 warehouse locations and roughly 100,000 resources. The cleanup statements at its end are commented out.
4. Copy `.env.example` to `.env`; set `DB_CONNECT` to `localhost:1521/XEPDB1` or `localhost:1521/FREEPDB1`, plus credentials. `POOL_MAX` defaults to 20.
5. Run `npm install`, then `npm start` (or `npm run dev`). Open http://localhost:3000.
6. Keep the server running with a populated Oracle database, then run `npm run test:concurrency` for races or `npm run test:load` for the 20-second autocannon run per endpoint. Both test scripts require the server to be running; the concurrency script also needs valid Oracle credentials in `.env`. Load test output is measured live and varies by machine/database.

## How the project maps to the review

- `sp_fulfill_request` uses strict two-phase locking: request row first, then resource row, holding locks through stock, request and allocation changes. Critical requests use `WAIT 10`; lower-priority requests use `NOWAIT` (priority-based wait-die style). The priority guard reserves stock for strictly higher scores; only a COMMANDER may override.
- `sp_allocate_nearest` calculates distance and locks a matching resource in one transaction, then creates the fulfilled request and immutable allocation record.
- `idx_loc_coords(latitude, longitude)` is a composite B+ tree. `GET /api/explain/nearby` defaults to a 50 km radius and returns Oracle's `DBMS_XPLAN` output so the index access can be reviewed after `seed_bulk.sql`.
- Supporting foreign-key/query indexes are `idx_res_loc`, `idx_req_res_status`, `idx_req_incident`, `idx_alloc_by`, and `idx_users_loc`.
- For manageable default API lists after bulk seeding, `/api/resources` and `/api/locations` hide bulk rows. Add `?include_bulk=1` to include them; `/api/resources` accepts `?limit=` (default 300, maximum 2,000). Nearby search and EXPLAIN continue to include all rows.
- `/api/resources/nearby` returns measured `query_ms`; `/api/metrics` reports rolling route latency percentiles.
- `trg_alloc_immutable` protects the audit log. `trg_med_isa` and `trg_res_type_guard` enforce the medical subtype; `users.location_id` is mandatory.
- The frontend includes a Light/Dark/System theme toggle, saved in local storage.

## API quick reference

Existing routes remain available: health, dashboard, users, locations, incidents, resources, nearby resources, requests, fulfill, reject and allocations. New routes include `POST /api/allocate-nearest`, `POST /api/queue/process`, `PATCH /api/incidents/:id/status`, `GET /api/metrics`, and `GET /api/explain/nearby`.

## Reset and troubleshooting

Run `reset.sql` then `schema.sql` to recreate the sample database. `/api/health` checks Oracle connectivity. Confirm the PDB service name, credentials and that Oracle is running if startup fails. The UI loads React, ReactDOM and htm from jsDelivr, so browser internet access is needed.
