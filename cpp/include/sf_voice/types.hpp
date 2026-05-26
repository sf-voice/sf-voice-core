#pragma once

#include <optional>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "error.hpp"

namespace sf_voice {

// ── result type ────────────────────────────────────────────────────────────
// simple ok/err container — no std::expected dependency, works on c++17.
// check ok before accessing value; check !ok before accessing error.
template <typename T>
struct Result {
    bool ok = false;
    T value{};
    SfVoiceMediaError error{};

    // factory helpers keep call-sites clean
    static Result success(T v) {
        Result r;
        r.ok = true;
        r.value = std::move(v);
        return r;
    }

    static Result failure(SfVoiceMediaError e) {
        Result r;
        r.ok = false;
        r.error = std::move(e);
        return r;
    }
};

// ── enums ──────────────────────────────────────────────────────────────────

// all states a processing task can be in
enum class TaskStatus {
    Pending,
    Indexing,
    Ready,
    Failed,
    Unknown  // fallback for forward-compat with new api values
};

inline TaskStatus task_status_from_string(const std::string& s) {
    if (s == "pending")  return TaskStatus::Pending;
    if (s == "indexing") return TaskStatus::Indexing;
    if (s == "ready")    return TaskStatus::Ready;
    if (s == "failed")   return TaskStatus::Failed;
    return TaskStatus::Unknown;
}

inline std::string task_status_to_string(TaskStatus s) {
    switch (s) {
        case TaskStatus::Pending:  return "pending";
        case TaskStatus::Indexing: return "indexing";
        case TaskStatus::Ready:    return "ready";
        case TaskStatus::Failed:   return "failed";
        default:                   return "unknown";
    }
}

// search modalities supported by POST /v1/search
enum class SearchType {
    Visual,
    Conversation,
    TextInVideo
};

inline std::string search_type_to_string(SearchType t) {
    switch (t) {
        case SearchType::Visual:       return "visual";
        case SearchType::Conversation: return "conversation";
        case SearchType::TextInVideo:  return "text_in_video";
        default:                       return "visual";
    }
}

// ── pagination ─────────────────────────────────────────────────────────────

struct PageInfo {
    int page       = 1;
    int limit      = 20;
    int total      = 0;
    bool has_more  = false;
};

inline void from_json(const nlohmann::json& j, PageInfo& p) {
    j.at("page").get_to(p.page);
    j.at("limit").get_to(p.limit);
    if (j.contains("total"))    j.at("total").get_to(p.total);
    if (j.contains("has_more")) j.at("has_more").get_to(p.has_more);
}

// ── core domain objects ────────────────────────────────────────────────────

// a single ingested asset
struct Asset {
    std::string id;
    std::string status;                     // raw string from api
    std::optional<std::string> title;
    std::optional<std::string> description;
    std::optional<std::string> url;         // source url if provided at ingest
    std::optional<std::string> created_at;
    std::optional<std::string> updated_at;
    nlohmann::json metadata;                // catch-all for extra fields
};

inline void from_json(const nlohmann::json& j, Asset& a) {
    j.at("id").get_to(a.id);
    j.at("status").get_to(a.status);
    if (j.contains("title")       && !j["title"].is_null())       a.title       = j["title"].get<std::string>();
    if (j.contains("description") && !j["description"].is_null()) a.description = j["description"].get<std::string>();
    if (j.contains("url")         && !j["url"].is_null())         a.url         = j["url"].get<std::string>();
    if (j.contains("created_at")  && !j["created_at"].is_null())  a.created_at  = j["created_at"].get<std::string>();
    if (j.contains("updated_at")  && !j["updated_at"].is_null())  a.updated_at  = j["updated_at"].get<std::string>();
    // store the whole object for forward-compat — callers can inspect unknown fields
    a.metadata = j;
}

// ── task ───────────────────────────────────────────────────────────────────

struct Task {
    std::string task_id;
    std::string asset_id;
    TaskStatus  status = TaskStatus::Unknown;
    std::string status_raw;                  // verbatim api string
    std::optional<std::string> error;
    std::optional<std::string> created_at;
    std::optional<std::string> completed_at;
};

inline void from_json(const nlohmann::json& j, Task& t) {
    j.at("task_id").get_to(t.task_id);
    j.at("asset_id").get_to(t.asset_id);
    j.at("status").get_to(t.status_raw);
    t.status = task_status_from_string(t.status_raw);
    if (j.contains("error")        && !j["error"].is_null())        t.error        = j["error"].get<std::string>();
    if (j.contains("created_at")   && !j["created_at"].is_null())   t.created_at   = j["created_at"].get<std::string>();
    if (j.contains("completed_at") && !j["completed_at"].is_null()) t.completed_at = j["completed_at"].get<std::string>();
}

// ── ingest ─────────────────────────────────────────────────────────────────

// request body for POST /v1/ingest — url or s3 key, everything else optional
struct IngestRequest {
    std::optional<std::string> url;          // remote media url
    std::optional<std::string> s3_key;       // S3 object key
    std::optional<std::string> title;
    std::optional<std::string> description;
    nlohmann::json extra;                    // any additional fields to forward
};

// 202 response from POST /v1/ingest
struct IngestResponse {
    std::string asset_id;
    std::string task_id;
    std::string status;
};

inline void from_json(const nlohmann::json& j, IngestResponse& r) {
    j.at("asset_id").get_to(r.asset_id);
    j.at("task_id").get_to(r.task_id);
    j.at("status").get_to(r.status);
}

// ── list assets ────────────────────────────────────────────────────────────

struct ListAssetsRequest {
    int page  = 1;
    int limit = 20;
};

struct AssetListResponse {
    std::vector<Asset> items;
    PageInfo page_info;
};

inline void from_json(const nlohmann::json& j, AssetListResponse& r) {
    j.at("items").get_to(r.items);
    if (j.contains("page_info")) {
        j.at("page_info").get_to(r.page_info);
    } else {
        // some apis inline page info at the top level — handle both shapes
        r.page_info = j.get<PageInfo>();
    }
}

// ── search ─────────────────────────────────────────────────────────────────

struct SearchRequest {
    std::string query;
    SearchType  type       = SearchType::Visual;
    int         page       = 1;
    int         limit      = 20;
    std::optional<std::string> asset_id;   // scope to one asset
};

// a single search hit
struct SearchResult {
    std::string asset_id;
    std::optional<double> score;
    std::optional<double> start_ms;
    std::optional<double> end_ms;
    std::optional<std::string> transcript_snippet;
    nlohmann::json metadata;
};

inline void from_json(const nlohmann::json& j, SearchResult& r) {
    j.at("asset_id").get_to(r.asset_id);
    if (j.contains("score")               && !j["score"].is_null())               r.score               = j["score"].get<double>();
    if (j.contains("start_ms")            && !j["start_ms"].is_null())            r.start_ms            = j["start_ms"].get<double>();
    if (j.contains("end_ms")              && !j["end_ms"].is_null())              r.end_ms              = j["end_ms"].get<double>();
    if (j.contains("transcript_snippet")  && !j["transcript_snippet"].is_null())  r.transcript_snippet  = j["transcript_snippet"].get<std::string>();
    r.metadata = j;
}

struct SearchResponse {
    std::vector<SearchResult> results;
    PageInfo page_info;
};

inline void from_json(const nlohmann::json& j, SearchResponse& r) {
    j.at("results").get_to(r.results);
    if (j.contains("page_info")) {
        j.at("page_info").get_to(r.page_info);
    } else {
        r.page_info = j.get<PageInfo>();
    }
}

// ── unit type for void-ish responses ─────────────────────────────────────
// used by delete_asset which returns 204 No Content
struct Empty {};

} // namespace sf_voice
