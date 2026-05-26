package com.sfvoice.demo.routes

import com.sfvoice.media.SearchMatchType
import com.sfvoice.media.SfVoiceMediaClient
import com.sfvoice.media.SfVoiceMediaException
import com.sfvoice.media.SearchRequest
import io.ktor.http.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable

@Serializable
data class SearchBody(
    val query: String,
    val types: List<String>? = null,
    val asset_ids: List<String>? = null,
    val threshold: Float? = null,
)

/**
 * Converts a string identifier to the corresponding SearchMatchType.
 *
 * @return The matching SearchMatchType for "visual", "conversation", or "text_in_video", or `null` if the string does not map to a known type.
 */
private fun String.toMatchType(): SearchMatchType? = when (this) {
    "visual"         -> SearchMatchType.Visual
    "conversation"   -> SearchMatchType.Conversation
    "text_in_video"  -> SearchMatchType.TextInVideo
    else             -> null
}

/**
 * Registers HTTP routes for searching and listing media assets.
 *
 * Exposes a POST /search endpoint that accepts a JSON body with search parameters and a GET /assets endpoint that lists assets with paging.
 *
 * POST /search:
 * - Accepts a JSON body matching SearchBody (fields: `query`, optional `types`, optional `asset_ids`, optional `threshold`).
 * - Converts `types` strings to internal match types before calling the client.
 * - On success responds with the client's search response; on failure responds with the SfVoiceMediaException status and an error object containing `code` and `message`.
 *
 * GET /assets:
 * - Accepts optional query parameters `page` (default 1) and `limit` (default 20).
 * - On success responds with the client's listAssets response; on failure responds with the SfVoiceMediaException status and an error object containing `code` and `message`.
 *
 * @param client Client used to perform search and asset listing operations.
 */
fun Route.searchRoutes(client: SfVoiceMediaClient) {
    // POST /search — semantic search
    post("/search") {
        val body = call.receive<SearchBody>()

        val matchTypes = body.types?.mapNotNull { it.toMatchType() }

        try {
            val req = SearchRequest(
                query = body.query,
                types = matchTypes,
                assetIds = body.asset_ids,
                threshold = body.threshold,
            )
            val resp = client.search(req)
            call.respond(resp)
        } catch (e: SfVoiceMediaException) {
            call.respond(HttpStatusCode.fromValue(e.status), mapOf("error" to mapOf("code" to e.code, "message" to e.message)))
        }
    }

    // GET /assets?page=1&limit=20
    get("/assets") {
        val page  = call.parameters["page"]?.toIntOrNull()  ?: 1
        val limit = call.parameters["limit"]?.toIntOrNull() ?: 20

        try {
            val resp = client.listAssets(page = page, limit = limit)
            call.respond(resp)
        } catch (e: SfVoiceMediaException) {
            call.respond(HttpStatusCode.fromValue(e.status), mapOf("error" to mapOf("code" to e.code, "message" to e.message)))
        }
    }
}
