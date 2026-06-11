package com.sfvoice.media

import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.coroutines.*
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

    /**
     * Throws an SfVoiceMediaException when the HTTP response status indicates an error.
     *
     * If the response body can be decoded as an `ApiErrorEnvelope`, the exception's `code`
     * and `message` are taken from that envelope; otherwise the exception uses
     * HTTP-derived defaults (`"http_error"` and a status-based message).
     *
     * @throws SfVoiceMediaException when `status.isSuccess()` is false.
     */

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
     * Submit a media file for ingestion.
     *
     * Initiates ingestion and returns the created task information immediately.
     *
     * @param request Details of the media to ingest and any ingestion options.
     * @return An IngestResponse containing the created task's ID and associated metadata.
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

    /**
     * Fetches the current state of an ingestion task.
     *
     * @param taskId The ID of the task to retrieve.
     * @return The requested Task containing its current status and metadata.
     */
    suspend fun getTask(taskId: String): Task {
        val response = http.get("$baseUrl/v1/tasks/$taskId") {
            header("X-API-Key", apiKey)
        }
        response.throwIfError()
        return response.body()
    }

    /**
     * Lists assets in the library with pagination.
     *
     * @param page Page number starting at 1.
     * @param limit Number of items to return per page.
     * @return An AssetListResponse containing the requested page of assets.
     */
    suspend fun listAssets(page: Int = 1, limit: Int = 20): AssetListResponse {
        val response = http.get("$baseUrl/v1/assets") {
            header("X-API-Key", apiKey)
            parameter("page", page)
            parameter("limit", limit)
        }
        response.throwIfError()
        return response.body()
    }

    /**
     * Retrieve an asset by its identifier.
     *
     * @param assetId The ID of the asset to fetch.
     * @return The asset with the specified ID.
     */
    suspend fun getAsset(assetId: String): Asset {
        val response = http.get("$baseUrl/v1/assets/$assetId") {
            header("X-API-Key", apiKey)
        }
        response.throwIfError()
        return response.body()
    }

    /**
     * Soft-delete the asset identified by [assetId], retaining the record but excluding it from list results.
     *
     * Completes successfully when the server responds with HTTP 204.
     *
     * @param assetId The identifier of the asset to soft-delete.
     * @throws SfVoiceMediaException if the HTTP response indicates an error.
     */
    suspend fun deleteAsset(assetId: String) {
        val response = http.delete("$baseUrl/v1/assets/$assetId") {
            header("X-API-Key", apiKey)
        }
        response.throwIfError()
    }

    /**
     * Performs a semantic search over indexed media.
     *
     * @param request The search query and any filters or pagination parameters to apply.
     * @return A SearchResponse containing matching results and associated metadata.
     */
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
     * Waits until the specified task reaches a terminal status and returns its final state.
     *
     * @param taskId The ID of the task to poll.
     * @param intervalMs Milliseconds between polls.
     * @param timeoutMs Maximum total wait time in milliseconds before giving up.
     * @return The final `Task` whose `status` is terminal.
     * @throws SfVoiceMediaPollTimeoutException if the timeout elapses before the task becomes terminal.
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

    // ── monitors ────────────────────────────────────────────────────────────

    /**
     * Creates a new monitor that watches for content matching the given text.
     *
     * @param request The monitor definition including search text and optional filters.
     * @return The created Monitor.
     */
    suspend fun createMonitor(request: CreateMonitorRequest): Monitor {
        val response = http.post("$baseUrl/v1/monitors") {
            header("X-API-Key", apiKey)
            contentType(ContentType.Application.Json)
            setBody(request)
        }
        response.throwIfError()
        return response.body()
    }

    /**
     * Lists all monitors owned by this API key.
     *
     * @return A MonitorListResponse containing the monitors and total count.
     */
    suspend fun listMonitors(): MonitorListResponse {
        val response = http.get("$baseUrl/v1/monitors") {
            header("X-API-Key", apiKey)
        }
        response.throwIfError()
        return response.body()
    }

    /**
     * Retrieves a single monitor by its identifier.
     *
     * @param monitorId The ID of the monitor to fetch.
     * @return The requested Monitor.
     */
    suspend fun getMonitor(monitorId: String): Monitor {
        val response = http.get("$baseUrl/v1/monitors/$monitorId") {
            header("X-API-Key", apiKey)
        }
        response.throwIfError()
        return response.body()
    }

    /**
     * Partially updates an existing monitor.
     *
     * Only fields present in [request] are modified; omitted fields remain unchanged.
     *
     * @param monitorId The ID of the monitor to update.
     * @param request The fields to patch.
     * @return The updated Monitor.
     */
    suspend fun updateMonitor(monitorId: String, request: UpdateMonitorRequest): Monitor {
        val response = http.patch("$baseUrl/v1/monitors/$monitorId") {
            header("X-API-Key", apiKey)
            contentType(ContentType.Application.Json)
            setBody(request)
        }
        response.throwIfError()
        return response.body()
    }

    /**
     * Deletes a monitor by its identifier.
     *
     * @param monitorId The ID of the monitor to delete.
     */
    suspend fun deleteMonitor(monitorId: String) {
        val response = http.delete("$baseUrl/v1/monitors/$monitorId") {
            header("X-API-Key", apiKey)
        }
        response.throwIfError()
    }

    /**
     * Lists events for a monitor with optional filtering and pagination.
     *
     * @param monitorId The ID of the monitor whose events to list.
     * @param matchedOnly When true, only return events where matched is true.
     * @param limit Maximum number of events to return.
     * @param offset Number of events to skip for pagination.
     * @return A MonitorEventListResponse containing events and total count.
     */
    suspend fun listMonitorEvents(
        monitorId: String,
        matchedOnly: Boolean = false,
        limit: Int = 50,
        offset: Int = 0,
    ): MonitorEventListResponse {
        val response = http.get("$baseUrl/v1/monitors/$monitorId/events") {
            header("X-API-Key", apiKey)
            parameter("matched_only", matchedOnly)
            parameter("limit", limit)
            parameter("offset", offset)
        }
        response.throwIfError()
        return response.body()
    }

    /**
     * Creates a monitor and polls it for matching events in the background.
     *
     * Returns an [AlertHandle] that can be used to stop polling and clean up the monitor.
     * The [callback] is invoked for each new matched event as it appears.
     *
     * ```kotlin
     * val handle = client.alert("breaking news about AI") { event ->
     *     println("match: score=${event.score}")
     * }
     * // ... later
     * handle.stop()
     * ```
     *
     * @param text The search text for the monitor.
     * @param callback Invoked for each new matched MonitorEvent.
     * @param slug Optional slug for the monitor.
     * @param projectId Optional project ID filter.
     * @param assetClass Optional asset class filter.
     * @param threshold Optional similarity threshold.
     * @param intervalMs Milliseconds between polls.
     * @return An AlertHandle to control the background polling.
     */
    suspend fun alert(
        text: String,
        callback: (MonitorEvent) -> Unit,
        slug: String? = null,
        projectId: String? = null,
        assetClass: String? = null,
        threshold: Float? = null,
        intervalMs: Long = 5_000L,
    ): AlertHandle {
        val monitor = createMonitor(
            CreateMonitorRequest(
                text = text,
                slug = slug,
                projectId = projectId,
                assetClass = assetClass,
                threshold = threshold,
            )
        )

        val seen = mutableSetOf<String>()
        val job = CoroutineScope(Dispatchers.Default).launch {
            while (isActive) {
                delay(intervalMs)
                val events = runCatching {
                    listMonitorEvents(monitor.id, matchedOnly = true)
                }.getOrNull() ?: continue

                for (event in events.items) {
                    if (seen.add(event.id)) {
                        callback(event)
                    }
                }
            }
        }

        return AlertHandle(
            monitorId = monitor.id,
            job = job,
            client = this,
        )
    }

    /**
     * Releases resources held by this client.
     *
     * Closes the underlying HTTP client, rendering this instance unusable for further requests.
     */
    override fun close() {
        http.close()
    }
}

/**
 * Handle returned by [SfVoiceMediaClient.alert] to control background polling.
 *
 * Call [stop] to cancel the polling coroutine and delete the underlying monitor.
 */
class AlertHandle(
    val monitorId: String,
    private val job: Job,
    private val client: SfVoiceMediaClient,
) {
    /**
     * Cancels the background polling and attempts to delete the monitor.
     *
     * The monitor deletion is best-effort; failures are silently ignored.
     */
    suspend fun stop() {
        job.cancel()
        job.join()
        runCatching { client.deleteMonitor(monitorId) }
    }
}
