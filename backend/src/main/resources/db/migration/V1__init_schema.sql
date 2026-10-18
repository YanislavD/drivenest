-- DriveNest v1 schema.
-- Enums are VARCHAR + CHECK (not Postgres ENUM) so new values are a simple migration.

CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE users (
    id         UUID PRIMARY KEY,                -- same id as the Supabase auth user
    full_name  VARCHAR(150) NOT NULL,
    phone      VARCHAR(30),
    role       VARCHAR(20)  NOT NULL DEFAULT 'CUSTOMER'
               CHECK (role IN ('CUSTOMER', 'STAFF', 'OWNER')),
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE cars (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    make            VARCHAR(50)   NOT NULL,
    model           VARCHAR(50)   NOT NULL,
    year            SMALLINT      NOT NULL CHECK (year BETWEEN 1990 AND 2100),
    fuel_type       VARCHAR(20)   NOT NULL
                    CHECK (fuel_type IN ('PETROL', 'DIESEL', 'HYBRID', 'ELECTRIC')),
    transmission    VARCHAR(20)   NOT NULL
                    CHECK (transmission IN ('MANUAL', 'AUTOMATIC')),
    seats           SMALLINT      NOT NULL CHECK (seats BETWEEN 1 AND 9),
    mileage_km      INTEGER       NOT NULL CHECK (mileage_km >= 0),
    tuv_valid_until DATE          NOT NULL,
    daily_price     NUMERIC(10,2) NOT NULL CHECK (daily_price > 0),
    status          VARCHAR(20)   NOT NULL DEFAULT 'AVAILABLE'
                    CHECK (status IN ('AVAILABLE', 'IN_MAINTENANCE', 'INACTIVE')),
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE car_images (
    id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    car_id   BIGINT       NOT NULL REFERENCES cars (id) ON DELETE CASCADE,
    url      VARCHAR(500) NOT NULL,
    position SMALLINT     NOT NULL DEFAULT 0
);
CREATE INDEX idx_car_images_car_id ON car_images (car_id);

CREATE TABLE reservations (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id UUID          NOT NULL REFERENCES users (id),
    car_id      BIGINT        NOT NULL REFERENCES cars (id),
    start_date  DATE          NOT NULL,
    end_date    DATE          NOT NULL,
    total_price NUMERIC(10,2) NOT NULL CHECK (total_price >= 0),
    status      VARCHAR(20)   NOT NULL DEFAULT 'PENDING'
                CHECK (status IN ('PENDING', 'CONFIRMED', 'ACTIVE', 'COMPLETED', 'CANCELLED')),
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT reservation_dates_valid CHECK (end_date >= start_date),

    -- The real guarantee against double bookings, even under concurrent requests:
    -- the same car cannot have two overlapping active reservations.
    -- '[]' = both start and end day are inclusive (whole days).
    CONSTRAINT no_overlapping_reservations
        EXCLUDE USING gist (car_id WITH =, daterange(start_date, end_date, '[]') WITH &&)
        WHERE (status IN ('PENDING', 'CONFIRMED', 'ACTIVE'))
);
CREATE INDEX idx_reservations_customer_id ON reservations (customer_id);
-- car_id is already covered by the leftmost column of the exclusion constraint's GiST index.

CREATE TABLE handovers (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reservation_id BIGINT      NOT NULL REFERENCES reservations (id),
    type           VARCHAR(10) NOT NULL CHECK (type IN ('PICKUP', 'RETURN')),
    mileage_km     INTEGER     NOT NULL CHECK (mileage_km >= 0),
    fuel_level     SMALLINT    NOT NULL CHECK (fuel_level BETWEEN 0 AND 100),
    notes          TEXT,
    staff_id       UUID        NOT NULL REFERENCES users (id),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- one pickup and one return per reservation
    CONSTRAINT uq_handover_per_type UNIQUE (reservation_id, type)
);
CREATE INDEX idx_handovers_staff_id ON handovers (staff_id);

CREATE TABLE damage_reports (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    car_id         BIGINT      NOT NULL REFERENCES cars (id),
    reservation_id BIGINT      REFERENCES reservations (id),
    description    TEXT        NOT NULL,
    photo_urls     TEXT[]      NOT NULL DEFAULT '{}',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_damage_reports_car_id ON damage_reports (car_id);
CREATE INDEX idx_damage_reports_reservation_id ON damage_reports (reservation_id);

CREATE TABLE maintenance_records (
    id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    car_id BIGINT        NOT NULL REFERENCES cars (id),
    type   VARCHAR(50)   NOT NULL,
    date   DATE          NOT NULL,
    cost   NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (cost >= 0),
    notes  TEXT
);
CREATE INDEX idx_maintenance_records_car_id ON maintenance_records (car_id);
