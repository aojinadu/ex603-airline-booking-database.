-- ============================================================================
-- Theme 5: Airline Booking
-- Target DBMS: PostgreSQL 14+
--
-- Role mapping:
--   actor    -> passengers
--   producer -> flights
--   event    -> bookings        (metric: fare_paid)
--   catalog  -> airports
--   junction -> flight_routes
-- ============================================================================

DROP TABLE IF EXISTS flight_routes CASCADE;
DROP TABLE IF EXISTS bookings      CASCADE;
DROP TABLE IF EXISTS airports      CASCADE;
DROP TABLE IF EXISTS flights       CASCADE;
DROP TABLE IF EXISTS passengers    CASCADE;


-- ----------------------------------------------------------------------------
-- 1. passengers  (actor)
--    The user who acts on the platform.
-- ----------------------------------------------------------------------------
CREATE TABLE passengers (
                            passenger_id   BIGINT GENERATED ALWAYS AS IDENTITY,
                            full_name      VARCHAR(120) NOT NULL,
                            email          VARCHAR(255) NOT NULL,
                            phone          VARCHAR(20),
                            date_of_birth  DATE,
                            created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),

                            CONSTRAINT pk_passengers          PRIMARY KEY (passenger_id),
                            CONSTRAINT uq_passengers_email    UNIQUE (email),
                            CONSTRAINT ck_passengers_name     CHECK (length(trim(full_name)) > 0),
                            CONSTRAINT ck_passengers_email    CHECK (email LIKE '%_@_%._%'),
                            CONSTRAINT ck_passengers_dob      CHECK (date_of_birth IS NULL
                                OR date_of_birth < CURRENT_DATE)
);


-- ----------------------------------------------------------------------------
-- 2. flights  (producer)
--    The supply-side entity being acted upon.
--    Activity flag: is_active.  Numeric filter attribute: base_fare.
-- ----------------------------------------------------------------------------
CREATE TABLE flights (
                         flight_id            BIGINT GENERATED ALWAYS AS IDENTITY,
                         flight_number        VARCHAR(8)    NOT NULL,
                         scheduled_departure  TIMESTAMPTZ   NOT NULL,
                         scheduled_arrival    TIMESTAMPTZ   NOT NULL,
                         base_fare            NUMERIC(10,2) NOT NULL,
                         seat_capacity        INTEGER       NOT NULL,
                         is_active            BOOLEAN       NOT NULL DEFAULT TRUE,

                         CONSTRAINT pk_flights            PRIMARY KEY (flight_id),
                         CONSTRAINT uq_flights_departure  UNIQUE (flight_number, scheduled_departure),
                         CONSTRAINT ck_flights_number     CHECK (flight_number ~ '^[A-Z0-9]{2}[0-9]{1,4}$'),
    CONSTRAINT ck_flights_times      CHECK (scheduled_arrival > scheduled_departure),
    CONSTRAINT ck_flights_fare       CHECK (base_fare >= 0),
    CONSTRAINT ck_flights_capacity   CHECK (seat_capacity > 0 AND seat_capacity <= 900)
);


-- ----------------------------------------------------------------------------
-- 3. airports  (catalog)
--    Descriptive dimension classifying flights.
-- ----------------------------------------------------------------------------
CREATE TABLE airports (
                          airport_id    INTEGER GENERATED ALWAYS AS IDENTITY,
                          iata_code     CHAR(3)      NOT NULL,
                          airport_name  VARCHAR(120) NOT NULL,
                          city          VARCHAR(80)  NOT NULL,
                          country_code  CHAR(2)      NOT NULL,

                          CONSTRAINT pk_airports          PRIMARY KEY (airport_id),
                          CONSTRAINT uq_airports_iata     UNIQUE (iata_code),
                          CONSTRAINT ck_airports_iata     CHECK (iata_code ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_airports_country  CHECK (country_code ~ '^[A-Z]{2}$')
);


-- ----------------------------------------------------------------------------
-- 4. bookings  (event)
--    High-volume fact table. One row per seat sold on a flight.
--    Aggregated metric: fare_paid.
-- ----------------------------------------------------------------------------
CREATE TABLE bookings (
                          booking_id      BIGINT GENERATED ALWAYS AS IDENTITY,
                          passenger_id    BIGINT        NOT NULL,
                          flight_id       BIGINT        NOT NULL,
                          booked_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
                          fare_paid       NUMERIC(10,2) NOT NULL,
                          seat_number     VARCHAR(4),
                          booking_status  VARCHAR(12)   NOT NULL DEFAULT 'CONFIRMED',

                          CONSTRAINT pk_bookings            PRIMARY KEY (booking_id),

                          CONSTRAINT fk_bookings_passenger  FOREIGN KEY (passenger_id)
                              REFERENCES passengers (passenger_id)
                              ON UPDATE CASCADE
                              ON DELETE RESTRICT,

                          CONSTRAINT fk_bookings_flight     FOREIGN KEY (flight_id)
                              REFERENCES flights (flight_id)
                              ON UPDATE CASCADE
                              ON DELETE RESTRICT,

                          CONSTRAINT ck_bookings_fare       CHECK (fare_paid >= 0),
                          CONSTRAINT ck_bookings_seat       CHECK (seat_number IS NULL
                              OR seat_number ~ '^[0-9]{1,3}[A-K]$'),
    CONSTRAINT ck_bookings_status     CHECK (booking_status IN
                                             ('CONFIRMED','CHECKED_IN','CANCELLED','COMPLETED'))
);

-- A physical seat can be held by only one live booking on a given flight.
-- Cancelled bookings are excluded so the seat can be resold.
CREATE UNIQUE INDEX uq_bookings_seat_per_flight
    ON bookings (flight_id, seat_number)
    WHERE seat_number IS NOT NULL AND booking_status <> 'CANCELLED';

-- Supporting indexes for the expected read patterns.
CREATE INDEX ix_bookings_passenger ON bookings (passenger_id, booked_at DESC);
CREATE INDEX ix_bookings_flight    ON bookings (flight_id);
CREATE INDEX ix_bookings_booked_at ON bookings (booked_at);


-- ----------------------------------------------------------------------------
-- 5. flight_routes  (junction)
--    Many-to-many link between flights and airports.
--    A flight touches 2 or more airports; an airport serves many flights.
-- ----------------------------------------------------------------------------
CREATE TABLE flight_routes (
                               flight_id      BIGINT      NOT NULL,
                               airport_id     INTEGER     NOT NULL,
                               stop_sequence  SMALLINT    NOT NULL,
                               stop_role      VARCHAR(12) NOT NULL,

                               CONSTRAINT pk_flight_routes         PRIMARY KEY (flight_id, airport_id),

                               CONSTRAINT fk_routes_flight         FOREIGN KEY (flight_id)
                                   REFERENCES flights (flight_id)
                                   ON UPDATE CASCADE
                                   ON DELETE CASCADE,

                               CONSTRAINT fk_routes_airport        FOREIGN KEY (airport_id)
                                   REFERENCES airports (airport_id)
                                   ON UPDATE CASCADE
                                   ON DELETE RESTRICT,

                               CONSTRAINT uq_routes_sequence       UNIQUE (flight_id, stop_sequence),
                               CONSTRAINT ck_routes_sequence       CHECK (stop_sequence >= 1),
                               CONSTRAINT ck_routes_role           CHECK (stop_role IN
                                                                          ('ORIGIN','STOPOVER','DESTINATION'))
);

-- Exactly one origin and one destination per flight.
CREATE UNIQUE INDEX uq_routes_one_origin
    ON flight_routes (flight_id) WHERE stop_role = 'ORIGIN';

CREATE UNIQUE INDEX uq_routes_one_destination
    ON flight_routes (flight_id) WHERE stop_role = 'DESTINATION';

CREATE INDEX ix_routes_airport ON flight_routes (airport_id);
