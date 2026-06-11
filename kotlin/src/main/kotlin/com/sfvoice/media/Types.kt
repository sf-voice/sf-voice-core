package com.sfvoice.media

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

// ── enums ─────────────────────────────────────────────────────────────────

@Serializable
enum class MediaType {
    @SerialName("video") Video,
    @SerialName("audio") Audio,
}

@Serializable
enum class SourceType {
    @SerialName("url") Url,
    @SerialName("s3") S3,
}

@Serializable
enum class TaskStatus {
    @SerialName("pending")  Pending,
    @SerialName("indexing") Indexing,
    @SerialName("ready")    Ready,
    @SerialName("failed")   Failed;

    val isTerminal: Boolean get() = this == Ready || this == Failed
}

@Serializable
enum class SearchMatchType {
    @SerialName("visual")         Visual,
    @SerialName("conversation")   Conversation,
    @SerialName("text_in_video")  TextInVideo,
}

// ── pagination ────────────────────────────────────────────────────────────

@Serializable
data class PageInfo(
    val total: Long,
    val page: Int,
    val limit: Int,
    @SerialName("next_page_token") val nextPageToken: String? = null,
)

// ── asset ─────────────────────────────────────────────────────────────────

@Serializable
data class Asset(
    val id: String,
    @SerialName("media_type")  val mediaType: MediaType,
    @SerialName("source_type") val sourceType: SourceType,
    val status: TaskStatus,
    val metadata: Map<String, String>? = null,
    @SerialName("duration_ms") val durationMs: Long? = null,
    @SerialName("created_at")  val createdAt: String,
    @SerialName("updated_at")  val updatedAt: String,
)

@Serializable
data class AssetListResponse(
    val items: List<Asset>,
    @SerialName("page_info") val pageInfo: PageInfo,
)

// ── ingest ────────────────────────────────────────────────────────────────

@Serializable
data class IngestRequest(
    val source: String,
    val url: String? = null,
    @SerialName("s3_key")    val s3Key: String? = null,
    @SerialName("media_type") val mediaType: MediaType? = null,
    val metadata: Map<String, String>? = null,
)

@Serializable
data class IngestResponse(
    @SerialName("asset_id") val assetId: String,
    @SerialName("task_id")  val taskId: String,
    val status: String,
)

// ── tasks ─────────────────────────────────────────────────────────────────

@Serializable
data class Task(
    @SerialName("task_id")      val taskId: String,
    @SerialName("asset_id")     val assetId: String,
    val status: TaskStatus,
    val error: String? = null,
    @SerialName("created_at")   val createdAt: String,
    @SerialName("completed_at") val completedAt: String? = null,
)

// ── search ────────────────────────────────────────────────────────────────

@Serializable
data class SearchRequest(
    val query: String,
    val types: List<SearchMatchType>? = null,
    @SerialName("asset_ids") val assetIds: List<String>? = null,
    val threshold: Float? = null,
    val page: Int? = null,
    val limit: Int? = null,
)

@Serializable
data class SearchResult(
    @SerialName("asset_id")      val assetId: String,
    val score: Float,
    @SerialName("start_ms")      val startMs: Long,
    @SerialName("end_ms")        val endMs: Long,
    @SerialName("match_type")    val matchType: SearchMatchType,
    @SerialName("thumbnail_url") val thumbnailUrl: String? = null,
)

@Serializable
data class SearchResponse(
    val results: List<SearchResult>,
    @SerialName("page_info") val pageInfo: PageInfo,
)

// ── monitors ─────────────────────────────────────────────────────────────

@Serializable
data class Monitor(
    val id: String,
    val slug: String,
    val text: String,
    val threshold: Float,
    val enabled: Boolean,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("project_id") val projectId: String? = null,
    @SerialName("asset_class") val assetClass: String? = null,
)

@Serializable
data class MonitorListResponse(
    val items: List<Monitor>,
    val total: Long,
)

@Serializable
data class CreateMonitorRequest(
    val text: String,
    val slug: String? = null,
    @SerialName("project_id") val projectId: String? = null,
    @SerialName("asset_class") val assetClass: String? = null,
    val threshold: Float? = null,
)

@Serializable
data class UpdateMonitorRequest(
    val text: String? = null,
    @SerialName("asset_class") val assetClass: String? = null,
    val threshold: Float? = null,
    val enabled: Boolean? = null,
)

@Serializable
data class MonitorEvent(
    val id: String,
    @SerialName("monitor_id") val monitorId: String,
    @SerialName("document_id") val documentId: String,
    val matched: Boolean,
    @SerialName("webhook_sent") val webhookSent: Boolean,
    @SerialName("created_at") val createdAt: String,
    @SerialName("asset_id") val assetId: String? = null,
    val score: Float? = null,
    @SerialName("match_detail") val matchDetail: JsonObject? = null,
)

@Serializable
data class MonitorEventListResponse(
    val items: List<MonitorEvent>,
    val total: Long,
)

// ── error envelope ────────────────────────────────────────────────────────

@Serializable
internal data class ApiErrorEnvelope(val error: ApiErrorBody)

@Serializable
internal data class ApiErrorBody(val code: String, val message: String)
