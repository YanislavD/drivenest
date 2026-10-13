package com.drivenest;

import org.springframework.boot.SpringApplication;

public class TestDrivenestApplication {

	public static void main(String[] args) {
		SpringApplication.from(DrivenestApplication::main).with(TestcontainersConfiguration.class).run(args);
	}

}
