package sh.sf-voice.demo;

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
     *   SF_VOICE_API_KEY=... gradle :java-example:bootRun
 */
@SpringBootApplication
public class App {
    /**
     * Bootstrap and run the Spring Boot application.
     *
     * @param args command-line arguments forwarded to the application
     */
    public static void main(String[] args) {
        SpringApplication.run(App.class, args);
    }
}
