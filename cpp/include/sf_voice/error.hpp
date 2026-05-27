#pragma once

#include <stdexcept>
#include <string>

namespace sf_voice {

// api error payload — carries the structured error returned by the server,
// or a synthetic error for network/parse failures.
struct SfVoiceMediaError {
    std::string code;      // machine-readable code (e.g. "not_found", "unauthorized")
    std::string message;   // human-readable description
    int status_code = 0;   // HTTP status; 0 for transport/parse errors

    SfVoiceMediaError() = default;

    SfVoiceMediaError(std::string code, std::string message, int status_code = 0)
        : code(std::move(code))
        , message(std::move(message))
        , status_code(status_code) {}

    // factory helpers — keep call sites readable
    static SfVoiceMediaError network(const std::string& msg) {
        return {"network_error", msg, 0};
    }
    static SfVoiceMediaError http(int status, const std::string& body) {
        return {"http_error", body, status};
    }
    static SfVoiceMediaError parse(const std::string& detail) {
        return {"parse_error", detail, 0};
    }
    static SfVoiceMediaError timeout(const std::string& task_id) {
        return {
            "poll_timeout",
            "task " + task_id + " did not reach a terminal state before the timeout",
            0
        };
    }
};

// throwable variant — wraps SfVoiceMediaError for exception-based usage
class SfVoiceMediaException : public std::runtime_error {
public:
    SfVoiceMediaError error;

    explicit SfVoiceMediaException(SfVoiceMediaError err)
        : std::runtime_error(err.message)
        , error(std::move(err)) {}

    SfVoiceMediaException(std::string code, std::string message, int status_code = 0)
        : SfVoiceMediaException(SfVoiceMediaError{std::move(code), std::move(message), status_code}) {}
};

} // namespace sf_voice
