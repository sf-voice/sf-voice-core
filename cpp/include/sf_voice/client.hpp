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

// default per-request timeout
static constexpr int kTimeoutMs = 30'000;

// parse the { "error": { "code", "message" } } envelope the API returns on errors
inline SfVoiceMediaError parse_api_error(int status_code, const std::string& body) {
    try {
        auto j = nlohmann::json::parse(body);
        if (j.contains("error") && j["error"].is_object()) {
            auto& e = j["error"];
            return SfVoiceMediaError{
                e.value("code",    "api_error"),
                e.value("message", body),
                status_code
            };
        }
    } catch (...) {}
    return SfVoiceMediaError::http(status_code, body);
}

template <typename T>
Result<T> parse_body(const std::string& body) {
    try {
        return Result<T>::success(nlohmann::json::parse(body).get<T>());
    } catch (const std::exception& ex) {
        return Result<T>::failure(SfVoiceMediaError::parse(ex.what()));
    }
}

template <typename T>
Result<T> handle_response(const cpr::Response& r) {
    if (r.error.code != cpr::ErrorCode::OK) {
        return Result<T>::failure(SfVoiceMediaError::network(r.error.message));
    }
    if (r.status_code < 200 || r.status_code >= 300) {
        return Result<T>::failure(parse_api_error(r.status_code, r.text));
    }
    return parse_body<T>(r.text);
}

// 204 No Content — nothing to parse
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
    explicit SfVoiceMedia(std::string api_key,
                          std::string base_url = "https://api.sf-voice.com")
        : api_key_(std::move(api_key))
        , base_url_(std::move(base_url))
    {
        // strip trailing slash so every path concat is predictable
        while (!base_url_.empty() && base_url_.back() == '/') {
            base_url_.pop_back();
        }
    }

    // ── ingest ───────────────────────────────────────────────────────────

    std::future<Result<IngestResponse>> ingest(IngestRequest request) {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url = std::move(base_url),
             auth     = std::move(auth),
             request  = std::move(request)]()
        {
            auto r = cpr::Post(
                cpr::Url{base_url + "/v1/ingest"},
                auth,
                cpr::Header{{"Content-Type", "application/json"}},
                cpr::Body{to_json(request).dump()},
                cpr::Timeout{detail::kTimeoutMs}
            );
            return detail::handle_response<IngestResponse>(r);
        });
    }

    // ── tasks ────────────────────────────────────────────────────────────

    std::future<Result<Task>> get_task(std::string task_id) {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url = std::move(base_url),
             auth     = std::move(auth),
             task_id  = std::move(task_id)]()
        {
            auto r = cpr::Get(
                cpr::Url{base_url + "/v1/tasks/" + task_id},
                auth,
                cpr::Timeout{detail::kTimeoutMs}
            );
            return detail::handle_response<Task>(r);
        });
    }

    // polls until the task reaches ready or failed, or the timeout elapses
    std::future<Result<Task>> poll_task(
        std::string task_id,
        std::chrono::milliseconds interval = std::chrono::milliseconds{1'500},
        std::chrono::milliseconds timeout  = std::chrono::milliseconds{120'000}
    ) {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url = std::move(base_url),
             auth     = std::move(auth),
             task_id  = std::move(task_id),
             interval,
             timeout]() -> Result<Task>
        {
            using clock = std::chrono::steady_clock;
            const auto deadline = clock::now() + timeout;

            while (clock::now() < deadline) {
                auto r = cpr::Get(
                    cpr::Url{base_url + "/v1/tasks/" + task_id},
                    auth,
                    cpr::Timeout{detail::kTimeoutMs}
                );
                auto result = detail::handle_response<Task>(r);

                if (!result.ok) return result;

                if (result.value.status == TaskStatus::Ready ||
                    result.value.status == TaskStatus::Failed) {
                    return result;
                }

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

    std::future<Result<AssetListResponse>> list_assets(ListAssetsRequest request = {}) {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url = std::move(base_url), auth = std::move(auth), request]()
        {
            auto r = cpr::Get(
                cpr::Url{base_url + "/v1/assets"},
                auth,
                cpr::Parameters{
                    {"page",  std::to_string(request.page)},
                    {"limit", std::to_string(request.limit)}
                },
                cpr::Timeout{detail::kTimeoutMs}
            );
            return detail::handle_response<AssetListResponse>(r);
        });
    }

    std::future<Result<Asset>> get_asset(std::string asset_id) {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url  = std::move(base_url),
             auth      = std::move(auth),
             asset_id  = std::move(asset_id)]()
        {
            auto r = cpr::Get(
                cpr::Url{base_url + "/v1/assets/" + asset_id},
                auth,
                cpr::Timeout{detail::kTimeoutMs}
            );
            return detail::handle_response<Asset>(r);
        });
    }

    std::future<Result<Empty>> delete_asset(std::string asset_id) {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url  = std::move(base_url),
             auth      = std::move(auth),
             asset_id  = std::move(asset_id)]()
        {
            auto r = cpr::Delete(
                cpr::Url{base_url + "/v1/assets/" + asset_id},
                auth,
                cpr::Timeout{detail::kTimeoutMs}
            );
            return detail::handle_response<Empty>(r);
        });
    }

    // ── search ───────────────────────────────────────────────────────────

    std::future<Result<SearchResponse>> search(SearchRequest request) {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url = std::move(base_url),
             auth     = std::move(auth),
             request  = std::move(request)]()
        {
            auto r = cpr::Post(
                cpr::Url{base_url + "/v1/search"},
                auth,
                cpr::Header{{"Content-Type", "application/json"}},
                cpr::Body{to_json(request).dump()},
                cpr::Timeout{detail::kTimeoutMs}
            );
            return detail::handle_response<SearchResponse>(r);
        });
    }

private:
    std::string api_key_;
    std::string base_url_;

    cpr::Header auth_header() const {
        return cpr::Header{{"X-API-Key", api_key_}};
    }
};

} // namespace sf_voice
