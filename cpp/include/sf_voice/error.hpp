#pragma once

#include <stdexcept>
#include <string>

namespace sf_voice {

// api error payload returned by the server: { error: { code, message } }
struct SfVoiceMediaError {
    std::string code;     // machine-readable error code from the api
    std::string message;  // human-readable description
    int status_code = 0;  // http status code (0 if not an http error)

    SfVoiceMediaError() = default;

    SfVoiceMediaError(std::string code, std::string message, int status_code = 0)
        : code(std::move(code))
        , message(std::move(message))
        , status_code(status_code) {}

    // convenience: build a local/network error that never reached the api
    static SfVoiceMediaError network(const std::string& message) {
        return SfVoiceMediaError{"network_error", message, 0};
    }

    // convenience: build an error from a non-2xx response with no json body
    static SfVoiceMediaError http(int status_code, const std::string& body) {
        return SfVoiceMediaError{"http_error", body, status_code};
    }

    // convenience: json parse failure
    static SfVoiceMediaError parse(const std::string& detail) {
        return SfVoiceMediaError{"parse_error", detail, 0};
    }

    // convenience: poll timeout
    static SfVoiceMediaError timeout(const std::string& task_id) {
        return SfVoiceMediaError{
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
