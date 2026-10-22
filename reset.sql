-- Run as user "hub" ONLY if you need to wipe everything and re-run schema.sql
DROP TABLE dispatch_allocations CASCADE CONSTRAINTS PURGE;
DROP TABLE resource_requests CASCADE CONSTRAINTS PURGE;
DROP TABLE medical_supplies CASCADE CONSTRAINTS PURGE;
DROP TABLE resources CASCADE CONSTRAINTS PURGE;
DROP TABLE disaster_incidents CASCADE CONSTRAINTS PURGE;
DROP TABLE users CASCADE CONSTRAINTS PURGE;
DROP TABLE locations CASCADE CONSTRAINTS PURGE;
DROP PROCEDURE sp_allocate_nearest;
DROP PROCEDURE sp_set_incident_status;
DROP PROCEDURE sp_process_queue;
DROP PROCEDURE sp_reject_request;
DROP PROCEDURE sp_fulfill_request;
