package com.drivenest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;

/** Verifies that the database itself enforces the booking rules (Flyway V1). */
@Import(TestcontainersConfiguration.class)
@SpringBootTest
class SchemaConstraintsTest {

	@Autowired
	JdbcTemplate jdbc;

	UUID customerId;
	long carId;

	@BeforeEach
	void setUp() {
		jdbc.update("DELETE FROM reservations");
		jdbc.update("DELETE FROM cars");
		jdbc.update("DELETE FROM users");

		customerId = UUID.randomUUID();
		jdbc.update("INSERT INTO users (id, full_name) VALUES (?, 'Test Customer')", customerId);
		carId = jdbc.queryForObject("""
				INSERT INTO cars (make, model, year, fuel_type, transmission, seats,
				                  mileage_km, tuv_valid_until, daily_price)
				VALUES ('VW', 'Golf', 2022, 'PETROL', 'MANUAL', 5, 10000, '2030-01-01', 50.00)
				RETURNING id
				""", Long.class);
	}

	private void reserve(String from, String to, String status) {
		jdbc.update("""
				INSERT INTO reservations (customer_id, car_id, start_date, end_date, total_price, status)
				VALUES (?, ?, ?::date, ?::date, 100.00, ?)
				""", customerId, carId, from, to, status);
	}

	@Test
	void overlappingReservationForSameCarIsRejected() {
		reserve("2030-06-10", "2030-06-15", "CONFIRMED");

		assertThatThrownBy(() -> reserve("2030-06-14", "2030-06-20", "PENDING"))
				.isInstanceOf(DataIntegrityViolationException.class);
	}

	@Test
	void sharingTheBoundaryDayCountsAsOverlap() {
		reserve("2030-06-10", "2030-06-15", "CONFIRMED");

		// the end date is inclusive, so a new booking cannot start on it
		assertThatThrownBy(() -> reserve("2030-06-15", "2030-06-18", "PENDING"))
				.isInstanceOf(DataIntegrityViolationException.class);
	}

	@Test
	void backToBackReservationsAreAllowed() {
		reserve("2030-06-10", "2030-06-15", "CONFIRMED");
		reserve("2030-06-16", "2030-06-20", "CONFIRMED");

		Integer count = jdbc.queryForObject("SELECT count(*) FROM reservations", Integer.class);
		assertThat(count).isEqualTo(2);
	}

	@Test
	void cancelledReservationDoesNotBlockTheDates() {
		reserve("2030-06-10", "2030-06-15", "CANCELLED");
		reserve("2030-06-10", "2030-06-15", "CONFIRMED");

		Integer count = jdbc.queryForObject("SELECT count(*) FROM reservations", Integer.class);
		assertThat(count).isEqualTo(2);
	}

	@Test
	void endDateBeforeStartDateIsRejected() {
		assertThatThrownBy(() -> reserve("2030-06-15", "2030-06-10", "PENDING"))
				.isInstanceOf(DataIntegrityViolationException.class);
	}
}
