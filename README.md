# Real-Time-Disaster-Resource-Allocation-Hub
A DBMS project for real-time disaster resource allocation using Oracle PL/SQL, geospatial distance calculation, and concurrency-safe transactions.
Overview

This project focuses on efficient disaster resource allocation using database optimization, geospatial distance calculation, and concurrency-safe transactions.

Key Features

Nearest Resource Allocation: Identifies nearby warehouses using latitude and longitude.

Distance Calculation: Uses the Haversine formula to estimate geographic distance.

Radius-Based Filtering: Filters candidate warehouses by a specified distance.

Concurrency-Safe Allocation: Uses Oracle transaction locking to help prevent conflicting allocations.

Database Indexing: Uses indexes to improve location-based query performance.

Load Testing: Evaluates backend performance under concurrent requests.

Tech Stack

Database: Oracle Database, SQL, PL/SQL

Backend: Node.js, Express

Frontend: HTML, CSS, JavaScript

Testing: Autocannon

Project Structure

schema.sql — Database schema and indexes

server.js — Backend server and API

public/ — Frontend files

seed_bulk.sql — Sample data generation

tests/load_test.js — Load testing

Setup

Install Node.js and configure an Oracle Database instance.

Configure the database connection using your own local environment variables.

Execute the SQL schema and sample-data scripts in the appropriate order.

Install the Node.js dependencies.

Start the backend server.

Open the frontend and test the resource allocation workflow.

Refer to the source code for the exact commands, environment variables, and database setup requirements.

Learning Outcomes

Database schema design and indexing

Stored procedures and transaction management

Geospatial queries and distance calculations

Concurrent transaction handling

Backend API development and performance testing
