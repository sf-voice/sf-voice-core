package sh.sf-voice.demo

import sh.sf-voice.demo.routes.ingestRoutes
import sh.sf-voice.demo.routes.searchRoutes
import sh.sf-voice.media.SfVoiceMediaClient
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.routing.*

/**
 * sf-voice media SDK demo — Ktor server with coroutine-native SDK.
 *
 * Same REST surface as the Java/Spring Boot demo but using suspend functions
 * throughout. Shows how a Kotlin-first platform would integrate the SDK.
 *
 * Run:
 *   SF_VOICE_API_KEY=... gradle :kotlin-example:run
 */
/**
 * Starts the Ktor Netty server for the sf-voice media SDK demo and registers HTTP routes.
 *
 * Reads SF_VOICE_API_KEY from the environment (throws if missing), SF_VOICE_BASE_URL (defaults to `https://api.sf-voice.com` if empty), and SERVER_PORT (defaults to `8081` if unset or not an integer), constructs an `SfVoiceMediaClient`, installs JSON content negotiation, and registers ingest and search routes before starting the server.
 *
 * @throws IllegalStateException if `SF_VOICE_API_KEY` is not set.
 */
fun main() {
    val apiKey = System.getenv("SF_VOICE_API_KEY")
        ?: error("required env var missing: SF_VOICE_API_KEY")
    val baseUrl = System.getenv("SF_VOICE_BASE_URL")?.takeIf { it.isNotBlank() }
        ?: "https://api.sf-voice.com"
    val port = System.getenv("SERVER_PORT")?.toIntOrNull() ?: 8081

    val sdkClient = SfVoiceMediaClient(apiKey = apiKey, baseUrl = baseUrl)

    embeddedServer(Netty, port = port) {
        install(ContentNegotiation) { json() }

        routing {
            ingestRoutes(sdkClient)
            searchRoutes(sdkClient)
        }
    }.start(wait = true)

    println("sf-voice kotlin demo running on http://0.0.0.0:$port")
}
