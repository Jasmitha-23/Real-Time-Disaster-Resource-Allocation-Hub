# Normalization notes (BCNF)

The following dependencies describe the schema's intended facts. Every determinant shown is a candidate key, so each relation is in BCNF.

| Table | Functional dependencies | Candidate key(s) |
|---|---|---|
| LOCATIONS | location_id → location_name, latitude, longitude, location_type | location_id |
| USERS | user_id → full_name, email, role, location_id; email → user_id, full_name, role, location_id | user_id; email (UNIQUE) |
| DISASTER_INCIDENTS | incident_id → title, severity_level, status, location_id, reported_at | incident_id |
| RESOURCES | resource_id → resource_name, resource_type, total_qty, available_qty, location_id | resource_id |
| MEDICAL_SUPPLIES | resource_id → is_cold_chain, storage_temp_celsius, expiry_date | resource_id |
| RESOURCE_REQUESTS | request_id → incident_id, resource_id, requested_by, requested_qty, priority_score, status, requested_at | request_id |
| DISPATCH_ALLOCATIONS | allocation_id → request_id, dispatched_by, allocated_qty, dispatched_at; request_id → allocation_id, dispatched_by, allocated_qty, dispatched_at | allocation_id; request_id (UNIQUE) |

`MEDICAL_SUPPLIES` is the MEDICAL specialization of `RESOURCES`: the subclass key is also a foreign key to the parent key, giving a shared-key 1:1 relationship. `trg_med_isa` enforces that the parent row has the MEDICAL discriminator, while `trg_res_type_guard` prevents invalidating an existing subtype.

`allocated_qty` is retained as the quantity actually dispatched at that time. It is an immutable historical fact recorded in the audit log, not a value to recalculate from the resource's changing stock or the request.
