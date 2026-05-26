package com.sfvoice.demo.routes

import com.sfvoice.media.MediaType
import com.sfvoice.media.SfVoiceMediaClient
import com.sfvoice.media.SfVoiceMediaException
import com.sfvoice.media.models.IngestRequest
import io.ktor.http.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable

@Serializable
data class IngestBody(val url: String, val media_type: String? = null)

/**
 * Registers ingestion-related HTTP routes on this Route: POST /ingest and GET /task/{id}.
 *
 * POST /ingest accepts a JSON body with `url` and an optional `media_type` (`"video"` or `"audio"`), submits an ingestion request, and responds with HTTP 202 and the client's response.
 * GET /task/{id} returns the task status for the specified `id`.
 *
 * Both routes translate SfVoiceMediaException into an HTTP response using the exception's status and a JSON body of the form:
 * `{ "error": { "code": <code>, "message": <message> } }`.
 *
 * @param client Client used to perform ingestion and task retrieval operations.
 */
fun Route.ingestRoutes(client: SfVoiceMediaClient) {
    // POST /ingest — submit a URL for ingestion
    post("/ingest") {
        val body = call.receive<IngestBody>()

        val mediaType = when (body.media_type) {
            "video" -> MediaType.Video
            "audio" -> MediaType.Audio
            else    -> null
        }

        try {
            val req = IngestRequest(
                source = "url",
                url = body.url,
                mediaType = mediaType,
            )
            val resp = client.ingest(req)
            call.respond(HttpStatusCode.Accepted, resp)
        } catch (e: SfVoiceMediaException) {
            call.respond(HttpStatusCode.fromValue(e.status), mapOf("error" to mapOf("code" to e.code, "message" to e.message)))
        }
    }

    // GET /task/{id} — poll task status
    get("/task/{id}") {
        val id = call.parameters["id"] ?: return@get call.respond(HttpStatusCode.BadRequest)

        try {
            val task = client.getTask(id)
            call.respond(task)
        } catch (e: SfVoiceMediaException) {
            call.respond(HttpStatusCode.fromValue(e.status), mapOf("error" to mapOf("code" to e.code, "message" to e.message)))
        }
    }
}
