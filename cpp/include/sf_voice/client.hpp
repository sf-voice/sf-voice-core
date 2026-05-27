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

/**
 * @brief Parse an API error envelope from an HTTP response body.
 *
 * Parses JSON bodies that follow the `{ "error": { "code": ..., "message": ... } }` shape
 * and constructs an SfVoiceMediaError containing the code, message, and HTTP status.
 * If the body is not valid JSON or the expected structure is missing, returns an HTTP-style
 * SfVoiceMediaError that contains the raw response body and status code.
 *
 * @param status_code HTTP status code associated with the response.
 * @param body Raw response body to parse.
 * @return SfVoiceMediaError Error representing either the parsed API error (`error.code`/`error.message`)
 *         or a fallback HTTP error containing the raw body.
 */
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
/**
 * @brief Deserialize a JSON string into a value of type `T`.
 *
 * Parses `body` as JSON and attempts to convert it into `T`; on success returns a successful Result containing the value, otherwise returns a failure Result with a parse error.
 *
 * @tparam T Type to deserialize into.
 * @param body JSON text to parse and deserialize.
 * @return Result<T> `success` containing the deserialized `T` on success, `failure` containing `SfVoiceMediaError::parse(...)` if parsing or deserialization fails.
 */
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
/**
 * Process an HTTP response and produce either a parsed value or an error result.
 *
 * @tparam T Type to deserialize the response body into.
 * @param r HTTP response whose network error, status code, and body determine the outcome.
 * @return Result containing the deserialized `T` on success.
 *         On failure, a `Result` with an `SfVoiceMediaError` describing a network error (when the request failed),
 *         an API/HTTP error (when the status code is not 2xx, using the API error envelope if present),
 *         or a parse error (when JSON deserialization fails).
 */
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
/**
 * @brief Convert an HTTP response with no expected body into a Result<Empty>.
 *
 * Produces a successful Result containing an Empty value for 2xx responses.
 * For transport-level errors returns a failure Result carrying a network error;
 * for non-2xx HTTP responses returns a failure Result with the parsed API error
 * (falls back to an HTTP error containing the raw body when parsing fails).
 *
 * @return Result<Empty> Successful result for 2xx responses; otherwise a failure
 *                         result describing the network or API error.
 */
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
    /**
     * @brief Construct an SfVoiceMedia client for interacting with the SF-Voice API.
     *
     * Initializes the client with the provided API key and base URL, and normalizes the
     * base URL by removing any trailing '/' characters so subsequent endpoint paths can
     * be concatenated consistently.
     *
     * @param api_key API key used for authenticating requests.
     * @param base_url Base URL for the SF-Voice API (defaults to "https://api.sf-voice.com").
     */
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

    /**
     * @brief Starts an ingest job for a media resource.
     *
     * Builds a JSON request from the provided fields and submits it to the
     * /v1/ingest endpoint to create an ingest task (and associated asset).
     *
     * @param request Request parameters; may include `url`, `s3_key`, `title`,
     *                `description`, and `extra` metadata to include in the body.
     * @return Result<IngestResponse> `IngestResponse` with created task and asset
     *         identifiers on success, or an `SfVoiceMediaError` describing network,
     *         HTTP, parsing, or API-level errors on failure.
     */
    inline std::future<Result<IngestResponse>> ingest(IngestRequest request) {
        auto base_url = base_url_;
        auto api_key  = api_key_;
        return std::async(std::launch::async,
            [base_url = std::move(base_url), api_key = std::move(api_key), request = std::move(request)]() {
            nlohmann::json body = request.extra.is_object() ? request.extra : nlohmann::json::object();
            if (request.url)         body["url"]         = *request.url;
            if (request.s3_key)      body["s3_key"]      = *request.s3_key;
            if (request.title)       body["title"]       = *request.title;
            if (request.description) body["description"] = *request.description;

            auto r = cpr::Post(
                cpr::Url{base_url + "/v1/ingest"},
                cpr::Header{
                    {"X-API-Key", api_key},
                    {"Content-Type", "application/json"},
                },
                cpr::Body{body.dump()},
                cpr::Timeout{30000}
            );
            return detail::handle_response<IngestResponse>(r);
        });
    }

    // ── task ─────────────────────────────────────────────────────────────

    /**
     * @brief Fetches the current state of a processing task by its identifier.
     *
     * Sends an authenticated GET request to the task endpoint and returns the parsed task state or an error.
     *
     * @param task_id The task identifier.
     * @return Result<Task> Containing the task on success, or a failure describing a network, HTTP, or parse error.
     */
    inline std::future<Result<Task>> get_task(std::string task_id) {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url = std::move(base_url), auth = std::move(auth), task_id = std::move(task_id)]() {
            auto r = cpr::Get(
                cpr::Url{base_url + "/v1/tasks/" + task_id},
                auth,
                cpr::Timeout{30000}
            );
            return detail::handle_response<Task>(r);
        });
    }

    // poll GET /v1/tasks/:id until the task reaches a terminal state (ready / failed)
    /**
     * Polls a task until it reaches a terminal state or the timeout elapses.
     *
     * Repeatedly requests the task status and stops when the task status is
     * `TaskStatus::Ready` or `TaskStatus::Failed`, an HTTP/network/parsing error
     * occurs, or the deadline defined by `timeout` is reached.
     *
     * @param task_id Identifier of the task to poll.
     * @param interval Time to wait between polling attempts.
     * @param timeout Maximum total duration to poll before giving up.
     * @return Result<Task> containing the final Task when the task reaches
     *         `TaskStatus::Ready` or `TaskStatus::Failed`. If a network/HTTP/parse
     *         error occurs, returns that error. If the deadline is reached first,
     *         returns a timeout error referring to `task_id`.
     */
    inline std::future<Result<Task>> poll_task(
        std::string task_id,
        std::chrono::milliseconds interval = std::chrono::milliseconds{1000},
        std::chrono::milliseconds timeout  = std::chrono::milliseconds{300000}
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
            auto deadline = clock::now() + timeout;

            while (clock::now() < deadline) {
                auto r = cpr::Get(
                    cpr::Url{base_url + "/v1/tasks/" + task_id},
                    auth,
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

    /**
     * @brief Fetches a paginated list of ingested assets.
     *
     * @param request Controls pagination: `request.page` is the page number and
     * `request.limit` is the number of items per page; both are sent as query parameters.
     * @return Result<AssetListResponse> The retrieved page of assets on success, or a failure describing a network, HTTP status, or parse error.
     */
    inline std::future<Result<AssetListResponse>> list_assets(ListAssetsRequest request = {}) {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url = std::move(base_url), auth = std::move(auth), request]() {
            auto r = cpr::Get(
                cpr::Url{base_url + "/v1/assets"},
                auth,
                cpr::Parameters{
                    {"page",  std::to_string(request.page)},
                    {"limit", std::to_string(request.limit)}
                },
                cpr::Timeout{30000}
            );
            return detail::handle_response<AssetListResponse>(r);
        });
    }

    /**
     * @brief Fetches metadata for a single asset by its ID.
     *
     * @param asset_id ID of the asset to retrieve.
     * @return Result<Asset> The retrieved asset metadata on success; a failure result containing an SfVoiceMediaError for network, HTTP status, or parse errors otherwise.
     */
    inline std::future<Result<Asset>> get_asset(std::string asset_id) {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url = std::move(base_url), auth = std::move(auth), asset_id = std::move(asset_id)]() {
            auto r = cpr::Get(
                cpr::Url{base_url + "/v1/assets/" + asset_id},
                auth,
                cpr::Timeout{30000}
            );
            return detail::handle_response<Asset>(r);
        });
    }

    /**
     * @brief Soft-delete an asset identified by its ID.
     *
     * Sends a DELETE request for the asset and treats a successful (2xx) response
     * — typically 204 No Content — as success.
     *
     * @param asset_id The identifier of the asset to delete.
     * @return Result<Empty> `Empty` on success, or a `SfVoiceMediaError` describing the failure.
     */
    inline std::future<Result<Empty>> delete_asset(std::string asset_id) {
        auto base_url = base_url_;
        auto auth     = auth_header();
        return std::async(std::launch::async,
            [base_url = std::move(base_url), auth = std::move(auth), asset_id = std::move(asset_id)]() {
            auto r = cpr::Delete(
                cpr::Url{base_url + "/v1/assets/" + asset_id},
                auth,
                cpr::Timeout{30000}
            );
            return detail::handle_response<Empty>(r);
        });
    }

    // ── search ───────────────────────────────────────────────────────────

    /**
     * @brief Perform a semantic search across ingested assets.
     *
     * @param request SearchRequest containing the search `query`, `type`, pagination (`page`, `limit`), and an optional `asset_id` to scope the search.
     * @return Result<SearchResponse> `SearchResponse` on success; on failure contains an `SfVoiceMediaError` describing network, HTTP status, or parse errors.
     */
    inline std::future<Result<SearchResponse>> search(SearchRequest request) {
        auto base_url = base_url_;
        auto api_key  = api_key_;
        return std::async(std::launch::async,
            [base_url = std::move(base_url), api_key = std::move(api_key), request = std::move(request)]() {
            nlohmann::json body = {
                {"query", request.query},
                {"type",  search_type_to_string(request.type)},
                {"page",  request.page},
                {"limit", request.limit}
            };
            if (request.asset_id) body["asset_id"] = *request.asset_id;

            auto r = cpr::Post(
                cpr::Url{base_url + "/v1/search"},
                cpr::Header{
                    {"X-API-Key", api_key},
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

    /**
     * @brief Builds an HTTP header containing the API key for authenticating requests.
     *
     * @return cpr::Header with the "X-API-Key" header set to the instance's API key.
     */
    inline cpr::Header auth_header() const {
        return cpr::Header{{"X-API-Key", api_key_}};
    }
};

} // namespace sf_voice
