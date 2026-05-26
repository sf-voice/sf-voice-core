package com.sfvoice.demo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * sf-voice media SDK demo — Spring Boot REST proxy.
 *
 * Demonstrates how an enterprise platform (e.g. Navan) would integrate the
 * sf-voice Java SDK behind a thin REST layer: ingest recordings, poll task
 * status, and run semantic searches — all via standard HTTP endpoints.
 *
 * Run:
 *   SF_VOICE_API_KEY=... ./gradlew :java-demo:bootRun
 */
@SpringBootApplication
public class App {
    public static void main(String[] args) {
        SpringApplication.run(App.class, args);
    }
}
