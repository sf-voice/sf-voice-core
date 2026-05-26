#pragma once

#include <chrono>
#include <future>
#include <string>
#include <thread>

#include <cpr/cpr.h>
#include <nlohmann/json.hpp>

#include "error.hpp"
#include "types.hpp"

namespace sf_voice {

// ── internal helpers ───────────────────────────────────────────────────────
namespace detail {

// parse the standard { error: { code, message } } envelope from the api
inline SfVoiceMediaError parse_api_error(int status_code, const std::string& body) {
    try {
        auto j = nlohmann::json::parse(body);
        if (j.contains("error") && j["error"].is_object()) {
            auto& e = j["error"];
            std::string code    = e.value("code", "api_error");
            std::string message = e.value("message", body);
            return SfVoiceMediaError{code, message, status_code};
        }
    } catch (...) {}
    // fall back to raw body when json is absent or malformed
    return SfVoiceMediaError::http(status_code, body);
}

// attempt to deserialise T from a json string — returns Result<T>
template <typename T>
inline Result<T> parse_body(const std::string& body) {
    try {
        auto j = nlohmann::json::parse(body);
        return Result<T>::success(j.get<T>());
    } catch (const std::exception& ex) {
        return Result<T>::failure(SfVoiceMediaError::parse(ex.what()));
    }
}

// check http status and return early on error; otherwise delegate to parse_body
template <typename T>
inline Result<T> handle_response(const cpr::Response& r) {
    if (r.error.code != cpr::ErrorCode::OK) {
        return Result<T>::failure(SfVoiceMediaError::network(r.error.message));
    }
    if (r.status_code < 200 || r.status_code >= 300) {
        return Result<T>::failure(parse_api_error(r.status_code, r.text));
    }
    return parse_body<T>(r.text);
}

// specialisation for Empty (204 No Content — no body to parse)
template <>
inline Result<Empty> handle_response<Empty>(const cpr::Response& r) {
    if (r.error.code != cpr::ErrorCode::OK) {
        return Result<Empty>::failure(SfVoiceMediaError::network(r.error.message));
    }
    if (r.status_code < 200 || r.status_code >= 300) {
        return Result<Empty>::failure(parse_api_error(r.status_code, r.text));
    }
    return Result<Empty>::success(Empty{});
}

} // namespace detail

// ── client ─────────────────────────────────────────────────────────────────

class SfVoiceMedia {
public:
    // api_key   — your X-API-Key secret
    // base_url  — override for self-hosted / staging deployments
    explicit SfVoiceMedia(std::string api_key,
                          std::string base_url = "https://api.sf-voice.com")
        : api_key_(std::move(api_key))
        , base_url_(std::move(base_url)) {
        // strip trailing slash so url construction stays clean
        while (!base_url_.empty() && base_url_.back() == '/') {
            base_url_.pop_back();
        }
    }

    // ── ingest ───────────────────────────────────────────────────────────

    // POST /v1/ingest — kicks off an ingest job, returns 202 with task + asset ids
    inline std::future<Result<IngestResponse>> ingest(IngestRequest request) {
        return std::async(std::launch::async, [this, request = std::move(request)]() {
            nlohmann::json body = request.extra.is_object() ? request.extra : nlohmann::json::object();
            if (request.url)         body["url"]         = *request.url;
            if (request.s3_key)      body["s3_key"]      = *request.s3_key;
            if (request.title)       body["title"]       = *request.title;
            if (request.description) body["description"] = *request.description;

            auto r = cpr::Post(
                cpr::Url{base_url_ + "/v1/ingest"},
                cpr::Header{
                    {"X-API-Key", api_key_},
                    {"Content-Type", "application/json"},
                },
                cpr::Body{body.dump()},
                cpr::Timeout{30000}
            );
            return detail::handle_response<IngestResponse>(r);
        });
    }

    // ── task ─────────────────────────────────────────────────────────────

    // GET /v1/tasks/:id — fetch the current state of a processing task
    inline std::future<Result<Task>> get_task(std::string task_id) {
        return std::async(std::launch::async, [this, task_id = std::move(task_id)]() {
            auto r = cpr::Get(
                cpr::Url{base_url_ + "/v1/tasks/" + task_id},
                auth_header(),
                cpr::Timeout{30000}
            );
            return detail::handle_response<Task>(r);
        });
    }

    // poll GET /v1/tasks/:id until the task reaches a terminal state (ready / failed)
    // or until the timeout elapses. polls every `interval`. returns the final Task.
    inline std::future<Result<Task>> poll_task(
        std::string task_id,
        std::chrono::milliseconds interval = std::chrono::milliseconds{1000},
        std::chrono::milliseconds timeout  = std::chrono::milliseconds{300000}
    ) {
        return std::async(std::launch::async,
            [this,
             task_id  = std::move(task_id),
             interval,
             timeout]() -> Result<Task>
        {
            using clock = std::chrono::steady_clock;
            auto deadline = clock::now() + timeout;

            while (clock::now() < deadline) {
                auto r = cpr::Get(
                    cpr::Url{base_url_ + "/v1/tasks/" + task_id},
                    auth_header(),
                    cpr::Timeout{30000}
                );
                auto result = detail::handle_response<Task>(r);

                if (!result.ok) {
                    return result; // surface errors immediately
                }

                // terminal states — stop polling
                if (result.value.status == TaskStatus::Ready ||
                    result.value.status == TaskStatus::Failed) {
                    return result;
                }

                // sleep only if we still have time left
                if (clock::now() + interval < deadline) {
                    std::this_thread::sleep_for(interval);
                } else {
                    break;
                }
            }

            return Result<Task>::failure(SfVoiceMediaError::timeout(task_id));
        });
    }

    // ── assets ───────────────────────────────────────────────────────────

    // GET /v1/assets?page=&limit= — paginated list of all ingested assets
    inline std::future<Result<AssetListResponse>> list_assets(ListAssetsRequest request = {}) {
        return std::async(std::launch::async, [this, request]() {
            auto r = cpr::Get(
                cpr::Url{base_url_ + "/v1/assets"},
                auth_header(),
                cpr::Parameters{
                    {"page",  std::to_string(request.page)},
                    {"limit", std::to_string(request.limit)}
                },
                cpr::Timeout{30000}
            );
            return detail::handle_response<AssetListResponse>(r);
        });
    }

    // GET /v1/assets/:id — fetch metadata for a single asset
    inline std::future<Result<Asset>> get_asset(std::string asset_id) {
        return std::async(std::launch::async, [this, asset_id = std::move(asset_id)]() {
            auto r = cpr::Get(
                cpr::Url{base_url_ + "/v1/assets/" + asset_id},
                auth_header(),
                cpr::Timeout{30000}
            );
            return detail::handle_response<Asset>(r);
        });
    }

    // DELETE /v1/assets/:id — soft-delete an asset; returns 204 No Content
    inline std::future<Result<Empty>> delete_asset(std::string asset_id) {
        return std::async(std::launch::async, [this, asset_id = std::move(asset_id)]() {
            auto r = cpr::Delete(
                cpr::Url{base_url_ + "/v1/assets/" + asset_id},
                auth_header(),
                cpr::Timeout{30000}
            );
            return detail::handle_response<Empty>(r);
        });
    }

    // ── search ───────────────────────────────────────────────────────────

    // POST /v1/search — semantic search across ingested assets
    inline std::future<Result<SearchResponse>> search(SearchRequest request) {
        return std::async(std::launch::async, [this, request = std::move(request)]() {
            nlohmann::json body = {
                {"query", request.query},
                {"type",  search_type_to_string(request.type)},
                {"page",  request.page},
                {"limit", request.limit}
            };
            if (request.asset_id) body["asset_id"] = *request.asset_id;

            auto r = cpr::Post(
                cpr::Url{base_url_ + "/v1/search"},
                cpr::Header{
                    {"X-API-Key", api_key_},
                    {"Content-Type", "application/json"},
                },
                cpr::Body{body.dump()},
                cpr::Timeout{30000}
            );
            return detail::handle_response<SearchResponse>(r);
        });
    }

private:
    std::string api_key_;
    std::string base_url_;

    // build the auth header for every request
    inline cpr::Header auth_header() const {
        return cpr::Header{{"X-API-Key", api_key_}};
    }
};

} // namespace sf_voice
