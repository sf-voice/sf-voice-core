package com.sfvoice.demo

import com.sfvoice.demo.routes.ingestRoutes
import com.sfvoice.demo.routes.searchRoutes
import com.sfvoice.media.SfVoiceMediaClient
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
 *   SF_VOICE_API_KEY=... ./gradlew :kotlin-demo:run
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
