#pragma once

#include <optional>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "error.hpp"

namespace sf_voice {

// ── result type ────────────────────────────────────────────────────────────
// ok/err container — no std::expected dependency, works on C++17.
// always check result.ok before accessing result.value.
template <typename T>
struct Result {
    bool ok = false;
    T value{};
    SfVoiceMediaError error{};

    static Result success(T v) {
        Result r;
        r.ok    = true;
        r.value = std::move(v);
        return r;
    }
    static Result failure(SfVoiceMediaError e) {
        Result r;
        r.ok    = false;
        r.error = std::move(e);
        return r;
    }
};

// ── enums ──────────────────────────────────────────────────────────────────

enum class TaskStatus {
    Pending,
    Indexing,
    Ready,
    Failed,
    Unknown  // forward-compat fallback for new api values
};

inline TaskStatus task_status_from_string(const std::string& s) {
    if (s == "pending")  return TaskStatus::Pending;
    if (s == "indexing") return TaskStatus::Indexing;
    if (s == "ready")    return TaskStatus::Ready;
    if (s == "failed")   return TaskStatus::Failed;
    return TaskStatus::Unknown;
}

// search modalities — matches the API's match_type field
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
    int  page      = 1;
    int  limit     = 20;
    int  total     = 0;
    bool has_more  = false;
};

inline void from_json(const nlohmann::json& j, PageInfo& p) {
    j.at("page").get_to(p.page);
    j.at("limit").get_to(p.limit);
    if (j.contains("total"))    j.at("total").get_to(p.total);
    if (j.contains("has_more")) j.at("has_more").get_to(p.has_more);
}

// ── asset ──────────────────────────────────────────────────────────────────

struct Asset {
    std::string id;
    std::string status;
    std::optional<std::string> title;
    std::optional<std::string> url;
    std::optional<std::string> created_at;
    std::optional<std::string> updated_at;
    nlohmann::json metadata;  // full response preserved for unknown fields
};

inline void from_json(const nlohmann::json& j, Asset& a) {
    j.at("id").get_to(a.id);
    j.at("status").get_to(a.status);
    if (j.contains("title")      && !j["title"].is_null())      a.title      = j["title"].get<std::string>();
    if (j.contains("url")        && !j["url"].is_null())        a.url        = j["url"].get<std::string>();
    if (j.contains("created_at") && !j["created_at"].is_null()) a.created_at = j["created_at"].get<std::string>();
    if (j.contains("updated_at") && !j["updated_at"].is_null()) a.updated_at = j["updated_at"].get<std::string>();
    a.metadata = j;
}

// ── task ───────────────────────────────────────────────────────────────────

struct Task {
    std::string task_id;
    std::string asset_id;
    TaskStatus  status     = TaskStatus::Unknown;
    std::string status_raw;
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

struct IngestRequest {
    std::string source;                        // "url" or "s3"
    std::string asset_id;                      // your ID — returned on every search result
    std::optional<std::string> asset_class;    // logical group for scoped search
    std::optional<std::string> url;            // required when source == "url"
    std::optional<std::string> s3_key;         // required when source == "s3"
    std::optional<std::string> media_type;     // "audio" or "video"
    nlohmann::json metadata;                   // flat key/value pairs for your own use
    nlohmann::json extra;                      // additional fields forwarded as-is
};

// builds the POST body — not a from_json since this goes outbound
inline nlohmann::json to_json(const IngestRequest& req) {
    nlohmann::json j = req.extra.is_object() ? req.extra : nlohmann::json::object();
    j["source"]   = req.source;
    j["asset_id"] = req.asset_id;
    if (req.asset_class) j["asset_class"] = *req.asset_class;
    if (req.url)         j["url"]         = *req.url;
    if (req.s3_key)      j["s3_key"]      = *req.s3_key;
    if (req.media_type)  j["media_type"]  = *req.media_type;
    if (req.metadata.is_object() && !req.metadata.empty()) j["metadata"] = req.metadata;
    return j;
}

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
    if (j.contains("page_info")) j.at("page_info").get_to(r.page_info);
    else r.page_info = j.get<PageInfo>();
}

// ── search ─────────────────────────────────────────────────────────────────

struct SearchRequest {
    std::string query;
    std::vector<SearchType> types;             // modalities to search; empty = all
    std::optional<std::string> asset_class;    // scope to one logical group
    std::vector<std::string> asset_ids;        // scope to specific assets
    std::optional<double> threshold;           // 0.0–1.0; higher = fewer, more confident
    int page  = 1;
    int limit = 20;
};

inline nlohmann::json to_json(const SearchRequest& req) {
    nlohmann::json j;
    j["query"] = req.query;
    if (!req.types.empty()) {
        auto arr = nlohmann::json::array();
        for (const auto& t : req.types) arr.push_back(search_type_to_string(t));
        j["types"] = arr;
    }
    if (req.asset_class)         j["asset_class"] = *req.asset_class;
    if (!req.asset_ids.empty())  j["asset_ids"]   = req.asset_ids;
    if (req.threshold)           j["threshold"]   = *req.threshold;
    j["page"]  = req.page;
    j["limit"] = req.limit;
    return j;
}

struct SearchResult {
    std::string asset_id;
    std::optional<double> score;
    std::optional<double> start_ms;
    std::optional<double> end_ms;
    std::optional<std::string> transcript_snippet;
    nlohmann::json metadata;  // full result preserved for unknown fields
};

inline void from_json(const nlohmann::json& j, SearchResult& r) {
    j.at("asset_id").get_to(r.asset_id);
    if (j.contains("score")              && !j["score"].is_null())              r.score              = j["score"].get<double>();
    if (j.contains("start_ms")           && !j["start_ms"].is_null())           r.start_ms           = j["start_ms"].get<double>();
    if (j.contains("end_ms")             && !j["end_ms"].is_null())             r.end_ms             = j["end_ms"].get<double>();
    if (j.contains("transcript_snippet") && !j["transcript_snippet"].is_null()) r.transcript_snippet = j["transcript_snippet"].get<std::string>();
    r.metadata = j;
}

struct SearchResponse {
    std::vector<SearchResult> results;
    PageInfo page_info;
};

inline void from_json(const nlohmann::json& j, SearchResponse& r) {
    j.at("results").get_to(r.results);
    if (j.contains("page_info")) j.at("page_info").get_to(r.page_info);
    else r.page_info = j.get<PageInfo>();
}

// placeholder for 204 No Content responses
struct Empty {};

} // namespace sf_voice
