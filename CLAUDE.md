# DriveNest – Car Rental Platform

Portfolio project for a CV (target roles: Junior Backend / DevOps / IT Support).
A car rental system: customers search and book cars by date range, staff handle
pickup/return, owners manage the fleet, prices and reports.

## How to work with me

- Communicate with me in **Bulgarian**. Code, comments, commit messages, README and docs in **English**.
- Work in **small steps**. One feature or layer at a time, then stop so I can review and run it.
- Before larger changes, briefly explain the plan and **why** (I need to be able to explain every decision in an interview).
- After each step: tell me how to run/test it and what to check.
- Write tests for business logic as you go, not at the end.
- Never commit secrets. Use `.env` files (git-ignored) and provide `.env.example`.
- Prefer simple, readable code over clever code.

## Tech stack

| Layer | Technology |
|---|---|
| Backend | Java 21, Spring Boot 3 (Web, Data JPA, Security / OAuth2 Resource Server, Validation, Actuator) |
| Database | PostgreSQL on **Supabase** (managed), schema via **Flyway** |
| Auth | **Supabase Auth** (frontend logs in, gets JWT; Spring validates the JWT via Supabase JWKS) |
| File storage | Supabase Storage (car images, damage photos) |
| Frontend | React + Vite, React Router, TanStack Query, React Hook Form + Zod, `supabase-js` (auth only) |
| Containers | Docker, Docker Compose |
| CI/CD | GitHub Actions (build, test, Docker images) |
| Testing | JUnit 5, Mockito, **Testcontainers** (Postgres) |
| Monitoring (v2) | Micrometer + Actuator `/actuator/prometheus`, Prometheus, Grafana, Blackbox exporter, Alertmanager |

### Architecture

```
React (Vite)  --login-->  Supabase Auth  --> JWT
React         --REST + JWT-->  Spring Boot API  --JDBC-->  Supabase Postgres
Spring Boot   --> Supabase Storage (images)
Prometheus    --> Spring /actuator/prometheus, Blackbox --> public endpoints
```

- React talks to Supabase **only for login**. All business data goes through the Spring Boot API.
- Spring Boot is the single source of business rules. No direct DB access from the frontend.

## Repository structure

```
/backend      Spring Boot app (Maven)
/frontend     React + Vite app
/monitoring   Prometheus, Grafana, Alertmanager, Blackbox configs (v2)
docker-compose.yml        local dev: local Postgres, backend, frontend
docker-compose.monitoring.yml   (v2)
.github/workflows/        CI pipelines
```

## Roles

- `CUSTOMER` – searches available cars, books, sees and cancels own reservations
- `STAFF` – performs pickup and return handovers, reports damage
- `OWNER` – manages cars, prices, maintenance, staff; sees dashboard and reports

Role is stored in our `users` table (linked to the Supabase user id), not trusted from the client.

## MVP scope (v1)

1. **Cars**: make, model, year, fuel type, transmission, seats, mileage, TÜV date, daily price, images, status (`AVAILABLE`, `IN_MAINTENANCE`, `INACTIVE`).
2. **Availability search**: `GET /api/cars/available?from=&to=` with filters (fuel, transmission, max price). Excludes cars with overlapping reservations, cars in maintenance and cars whose TÜV expires before the end date.
3. **Booking**: price = days × daily price, 10% discount for 7+ days. **No double bookings, even under concurrent requests.**
4. **Handover**: pickup and return record mileage, fuel level, notes, photos. On return, automatic extra charges for missing fuel, extra kilometers (over a daily limit) and late return.
5. **Owner admin panel**: cars CRUD, timeline of all cars and reservations, basic dashboard (utilization, revenue this month).
6. **Docker Compose** for local dev and **GitHub Actions** CI with Testcontainers tests.

### Later versions

- **v2**: extras (child seat, additional driver), seasonal prices, deposit; email confirmations and reminders (pickup tomorrow, TÜV/service due); PDF contract/invoice; monitoring stack; online deployment.
- **v3**: multi-tenant (each rental company gets its own admin and booking page, `organization_id` on all tables + Postgres RLS as second layer); Stripe payments (test mode); mobile-friendly staff view; i18n (DE / EN / BG).

## Data model (v1)

- `users` – id (UUID = Supabase auth user id), full_name, phone, role, created_at
- `cars` – id, make, model, year, fuel_type, transmission, seats, mileage_km, tuv_valid_until, daily_price, status, created_at
- `car_images` – id, car_id, url, position
- `reservations` – id, customer_id, car_id, start_date, end_date, total_price, status (`PENDING`, `CONFIRMED`, `ACTIVE`, `COMPLETED`, `CANCELLED`), created_at
- `handovers` – id, reservation_id, type (`PICKUP`, `RETURN`), mileage_km, fuel_level (0–100), notes, staff_id, created_at
- `damage_reports` – id, car_id, reservation_id, description, photo_urls, created_at
- `maintenance_records` – id, car_id, type, date, cost, notes

Money: `NUMERIC(10,2)` in DB, `BigDecimal` in Java. Dates for reservations: `DATE` (whole days) in v1.

## Key technical decisions

### Preventing double bookings (core interview topic)
- Enforced **in the database** with a Postgres exclusion constraint, so it holds even with concurrent requests:
  ```sql
  CREATE EXTENSION IF NOT EXISTS btree_gist;
  ALTER TABLE reservations ADD CONSTRAINT no_overlapping_reservations
    EXCLUDE USING gist (car_id WITH =, daterange(start_date, end_date, '[]') WITH &&)
    WHERE (status IN ('PENDING', 'CONFIRMED', 'ACTIVE'));
  ```
- The service layer also checks availability for a friendly error message, but the constraint is the real guarantee. Translate the constraint violation into HTTP 409 Conflict.
- Must have an integration test: many threads try to book the same car for the same dates at once, exactly one succeeds.

### Supabase connection
- Use the **Supavisor pooler** connection string (direct connection is IPv6-only, which often fails in Docker / GitHub Actions).
- Prefer **session mode (port 5432)**. If transaction mode (6543) is used, add `prepareThreshold=0` to the JDBC URL.
- Schema changes only through **Flyway migrations** (`backend/src/main/resources/db/migration`), never manually in the Supabase UI.
- Local dev and tests use a local Postgres container / Testcontainers, not Supabase.

### Security
- Spring Security as OAuth2 Resource Server, validating Supabase JWTs (issuer + JWKS from the Supabase project).
- Map the user's role from our `users` table into Spring authorities.
- Customers can only see and modify their own reservations (check ownership in the service layer).

### API conventions
- REST under `/api`, JSON, DTOs (never expose JPA entities directly).
- Validation with Bean Validation; global `@RestControllerAdvice` returning consistent error JSON.
- Layering: controller → service → repository. Business rules live in services.

## Commands

(fill in as the project grows)

```
# backend
cd backend && ./mvnw spring-boot:run
cd backend && ./mvnw test

# frontend
cd frontend && npm install && npm run dev

# everything locally
docker compose up --build
```

## Environment variables (see .env.example)

- `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`
- `SUPABASE_URL`, `SUPABASE_JWT_ISSUER`, `SUPABASE_JWKS_URL`
- `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_API_BASE_URL`

## Current status

- [x] Repo and folder structure
- [ ] Spring Boot project generated, connects to local Postgres
- [ ] First Flyway migration (all v1 tables + exclusion constraint)
- [ ] Supabase JWT validation + `/api/me`
- [ ] Cars CRUD (owner) + availability search
- [ ] Booking with price calculation + concurrency test
- [ ] Pickup / return handovers with extra charges
- [ ] React: login, search, booking, my reservations
- [ ] React: owner admin panel + timeline
- [ ] Docker Compose + GitHub Actions CI

Update this checklist as features are completed.
