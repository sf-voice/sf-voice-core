package com.sfvoice.media

import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.coroutines.delay
import kotlinx.serialization.json.Json

/**
 * coroutine-based client for the sf-voice media API.
 *
 * ```kotlin
 * val client = SfVoiceMediaClient(
 *     apiKey = System.getenv("SF_VOICE_API_KEY"),
 *     baseUrl = "https://api.sf-voice.com",
 * )
 * ```
 *
 * call [close] when done to release the underlying HTTP connection pool.
 */
class SfVoiceMediaClient(
    private val apiKey: String,
    baseUrl: String = "https://api.sf-voice.com",
) : AutoCloseable {

    private val baseUrl = baseUrl.trimEnd('/')

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = false
    }

    private val http = HttpClient(CIO) {
        install(ContentNegotiation) {
            json(json)
        }
    }

    // ── internal helpers ───────────────────────────────────────────────────

    private suspend fun HttpResponse.throwIfError() {
        if (status.isSuccess()) return
        val body = runCatching { bodyAsText() }.getOrNull()
        val envelope = body?.let {
            runCatching { json.decodeFromString<ApiErrorEnvelope>(it) }.getOrNull()
        }
        throw SfVoiceMediaException(
            code = envelope?.error?.code ?: "http_error",
            message = envelope?.error?.message ?: "request failed with status ${status.value}",
            status = status.value,
        )
    }

    // ── public API ─────────────────────────────────────────────────────────

    /**
     * submit a media file for ingestion. returns immediately with a [task_id]
     * you can poll with [getTask] or [pollTask].
     */
    suspend fun ingest(request: IngestRequest): IngestResponse {
        val response = http.post("$baseUrl/v1/ingest") {
            header("X-API-Key", apiKey)
            contentType(ContentType.Application.Json)
            setBody(request)
        }
        response.throwIfError()
        return response.body()
    }

    /** fetch the current state of an ingestion task. */
    suspend fun getTask(taskId: String): Task {
        val response = http.get("$baseUrl/v1/tasks/$taskId") {
            header("X-API-Key", apiKey)
        }
        response.throwIfError()
        return response.body()
    }

    /** list assets in the library with pagination. */
    suspend fun listAssets(page: Int = 1, limit: Int = 20): AssetListResponse {
        val response = http.get("$baseUrl/v1/assets") {
            header("X-API-Key", apiKey)
            parameter("page", page)
            parameter("limit", limit)
        }
        response.throwIfError()
        return response.body()
    }

    /** fetch a single asset by ID. */
    suspend fun getAsset(assetId: String): Asset {
        val response = http.get("$baseUrl/v1/assets/$assetId") {
            header("X-API-Key", apiKey)
        }
        response.throwIfError()
        return response.body()
    }

    /**
     * soft-delete an asset. the backend retains the record but excludes it
     * from list results. resolves Unit on HTTP 204.
     */
    suspend fun deleteAsset(assetId: String) {
        val response = http.delete("$baseUrl/v1/assets/$assetId") {
            header("X-API-Key", apiKey)
        }
        response.throwIfError()
    }

    /** run a semantic search across indexed media. */
    suspend fun search(request: SearchRequest): SearchResponse {
        val response = http.post("$baseUrl/v1/search") {
            header("X-API-Key", apiKey)
            contentType(ContentType.Application.Json)
            setBody(request)
        }
        response.throwIfError()
        return response.body()
    }

    /**
     * poll [getTask] until the task reaches a terminal state, then return the final [Task].
     *
     * @param taskId      the task to poll.
     * @param intervalMs  milliseconds between polls (default 1500).
     * @param timeoutMs   max total wait time in ms (default 120_000).
     * @throws SfVoiceMediaPollTimeoutException if the timeout elapses.
     */
    suspend fun pollTask(
        taskId: String,
        intervalMs: Long = 1_500L,
        timeoutMs: Long = 120_000L,
    ): Task {
        val deadline = System.currentTimeMillis() + timeoutMs

        while (true) {
            val task = getTask(taskId)
            if (task.status.isTerminal) return task

            val remaining = deadline - System.currentTimeMillis()
            if (remaining <= 0) throw SfVoiceMediaPollTimeoutException(taskId, timeoutMs)

            delay(minOf(intervalMs, remaining))
        }
    }

    override fun close() {
        http.close()
    }
}
