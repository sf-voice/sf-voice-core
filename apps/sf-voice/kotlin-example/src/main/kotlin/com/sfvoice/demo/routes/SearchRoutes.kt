package com.sfvoice.demo.routes

import com.sfvoice.media.SearchMatchType
import com.sfvoice.media.SfVoiceMediaClient
import com.sfvoice.media.SfVoiceMediaException
import com.sfvoice.media.models.SearchRequest
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

private fun String.toMatchType(): SearchMatchType? = when (this) {
    "visual"         -> SearchMatchType.Visual
    "conversation"   -> SearchMatchType.Conversation
    "text_in_video"  -> SearchMatchType.TextInVideo
    else             -> null
}

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
