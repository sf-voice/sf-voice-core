#pragma once

#include <atomic>
#include <chrono>
#include <functional>
#include <future>
#include <memory>
#include <set>
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

// ── alert handle ──────────────────────────────────────────────────────────
// returned by alert() — stops the background poll thread on destruction.

class SfVoiceMedia; // forward declaration

struct AlertHandle {
    std::string monitor_id;

    void stop() {
        if (!stopped_ || stopped_->exchange(true)) return;
        if (thread_.joinable()) thread_.join();
        auto r = cpr::Delete(
            cpr::Url{base_url_ + "/v1/monitors/" + monitor_id},
            auth_,
            cpr::Timeout{5000}
        );
        (void)r;
    }

    ~AlertHandle() { if (stopped_ && !stopped_->load()) stop(); }

    AlertHandle(const AlertHandle&) = delete;
    AlertHandle& operator=(const AlertHandle&) = delete;
    AlertHandle(AlertHandle&&) = default;
    AlertHandle& operator=(AlertHandle&&) = default;

private:
    friend class SfVoiceMedia;
    friend struct Result<AlertHandle>;
    AlertHandle() : stopped_(std::make_shared<std::atomic<bool>>(false)) {}

    std::shared_ptr<std::atomic<bool>> stopped_;
    std::thread thread_;
    std::string base_url_;
    cpr::Header auth_;
};

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

    // ── monitors ────────────────────────────────────────────────────────

    std::future<Result<Monitor>> create_monitor(CreateMonitorRequest request) {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url = std::move(base_url),
             auth     = std::move(auth),
             request  = std::move(request)]()
        {
            auto r = cpr::Post(
                cpr::Url{base_url + "/v1/monitors"},
                auth,
                cpr::Header{{"Content-Type", "application/json"}},
                cpr::Body{to_json(request).dump()},
                cpr::Timeout{detail::kTimeoutMs}
            );
            return detail::handle_response<Monitor>(r);
        });
    }

    std::future<Result<MonitorListResponse>> list_monitors() {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url = std::move(base_url), auth = std::move(auth)]()
        {
            auto r = cpr::Get(
                cpr::Url{base_url + "/v1/monitors"},
                auth,
                cpr::Timeout{detail::kTimeoutMs}
            );
            return detail::handle_response<MonitorListResponse>(r);
        });
    }

    std::future<Result<Monitor>> get_monitor(std::string monitor_id) {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url   = std::move(base_url),
             auth       = std::move(auth),
             monitor_id = std::move(monitor_id)]()
        {
            auto r = cpr::Get(
                cpr::Url{base_url + "/v1/monitors/" + monitor_id},
                auth,
                cpr::Timeout{detail::kTimeoutMs}
            );
            return detail::handle_response<Monitor>(r);
        });
    }

    std::future<Result<Monitor>> update_monitor(std::string monitor_id,
                                                UpdateMonitorRequest request) {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url   = std::move(base_url),
             auth       = std::move(auth),
             monitor_id = std::move(monitor_id),
             request    = std::move(request)]()
        {
            auto r = cpr::Patch(
                cpr::Url{base_url + "/v1/monitors/" + monitor_id},
                auth,
                cpr::Header{{"Content-Type", "application/json"}},
                cpr::Body{to_json(request).dump()},
                cpr::Timeout{detail::kTimeoutMs}
            );
            return detail::handle_response<Monitor>(r);
        });
    }

    std::future<Result<Empty>> delete_monitor(std::string monitor_id) {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url   = std::move(base_url),
             auth       = std::move(auth),
             monitor_id = std::move(monitor_id)]()
        {
            auto r = cpr::Delete(
                cpr::Url{base_url + "/v1/monitors/" + monitor_id},
                auth,
                cpr::Timeout{detail::kTimeoutMs}
            );
            return detail::handle_response<Empty>(r);
        });
    }

    std::future<Result<MonitorEventListResponse>> list_monitor_events(
        std::string monitor_id,
        bool matched_only = false,
        int limit  = 50,
        int offset = 0
    ) {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url     = std::move(base_url),
             auth         = std::move(auth),
             monitor_id   = std::move(monitor_id),
             matched_only,
             limit,
             offset]()
        {
            auto r = cpr::Get(
                cpr::Url{base_url + "/v1/monitors/" + monitor_id + "/events"},
                auth,
                cpr::Parameters{
                    {"matched_only", matched_only ? "true" : "false"},
                    {"limit",        std::to_string(limit)},
                    {"offset",       std::to_string(offset)}
                },
                cpr::Timeout{detail::kTimeoutMs}
            );
            return detail::handle_response<MonitorEventListResponse>(r);
        });
    }

    // ── alert (high-level convenience) ──────────────────────────────────
    // creates a monitor, then polls for matched events on a background
    // thread. returns an AlertHandle whose stop() tears everything down.

    Result<AlertHandle> alert(
        std::string text,
        std::function<void(MonitorEvent)> callback,
        CreateMonitorRequest opts = {},
        std::chrono::milliseconds interval = std::chrono::milliseconds{5000}
    ) {
        // merge text into opts
        opts.text = std::move(text);

        // synchronously create the monitor
        auto create_result = create_monitor(std::move(opts)).get();
        if (!create_result.ok) {
            return Result<AlertHandle>::failure(create_result.error);
        }

        AlertHandle handle;
        handle.monitor_id = create_result.value.id;
        handle.base_url_  = base_url_;
        handle.auth_      = auth_header();

        // capture what the thread needs by value — stopped is a shared_ptr
        // so the thread and the (moved) handle share the same flag
        auto poll_base_url   = base_url_;
        auto poll_auth       = auth_header();
        auto poll_monitor_id = handle.monitor_id;
        auto stopped         = handle.stopped_;

        handle.thread_ = std::thread(
            [poll_base_url = std::move(poll_base_url),
             poll_auth     = std::move(poll_auth),
             poll_monitor_id = std::move(poll_monitor_id),
             callback      = std::move(callback),
             interval,
             stopped       = std::move(stopped)]()
        {
            std::set<std::string> seen_ids;

            while (!stopped->load()) {
                auto r = cpr::Get(
                    cpr::Url{poll_base_url + "/v1/monitors/" + poll_monitor_id + "/events"},
                    poll_auth,
                    cpr::Parameters{
                        {"matched_only", "true"},
                        {"limit",        "50"},
                        {"offset",       "0"}
                    },
                    cpr::Timeout{detail::kTimeoutMs}
                );

                if (r.error.code == cpr::ErrorCode::OK &&
                    r.status_code >= 200 && r.status_code < 300)
                {
                    auto parsed = detail::parse_body<MonitorEventListResponse>(r.text);
                    if (parsed.ok) {
                        for (auto& ev : parsed.value.items) {
                            if (seen_ids.insert(ev.id).second) {
                                callback(std::move(ev));
                            }
                        }
                    }
                }

                // sleep in short increments so stop() isn't blocked for the full interval
                auto remaining = interval;
                const auto step = std::chrono::milliseconds{250};
                while (remaining > std::chrono::milliseconds{0} && !stopped->load()) {
                    auto sleep_for = std::min(remaining, step);
                    std::this_thread::sleep_for(sleep_for);
                    remaining -= sleep_for;
                }
            }
        });

        return Result<AlertHandle>::success(std::move(handle));
    }

private:
    std::string api_key_;
    std::string base_url_;

    cpr::Header auth_header() const {
        return cpr::Header{{"X-API-Key", api_key_}};
    }
};

} // namespace sf_voice
