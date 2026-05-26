#pragma once

#include <stdexcept>
#include <string>

namespace sf_voice {

// api error payload returned by the server: { error: { code, message } }
struct SfVoiceMediaError {
    std::string code;     // machine-readable error code from the api
    std::string message;  // human-readable description
    int status_code = 0;  /**
 * @brief Default-initializes an SfVoiceMediaError.
 *
 * Leaves `code` and `message` empty and sets `status_code` to 0 (indicating not an HTTP error).
 */

    SfVoiceMediaError() = default;

    /**
         * @brief Construct an SfVoiceMediaError with the provided error code, message, and optional HTTP status.
         *
         * @param code Machine-readable error code.
         * @param message Human-readable error description.
         * @param status_code HTTP status code associated with the error; 0 when there is no HTTP status (default 0).
         */
        SfVoiceMediaError(std::string code, std::string message, int status_code = 0)
        : code(std::move(code))
        , message(std::move(message))
        , status_code(status_code) {}

    /**
     * @brief Create an SfVoiceMediaError representing a network/local error that did not reach the API.
     *
     * @param message Human-readable error description.
     * @return SfVoiceMediaError Error object with `code` set to "network_error", `message` set to the given value, and `status_code` set to 0.
     */
    static SfVoiceMediaError network(const std::string& message) {
        return SfVoiceMediaError{"network_error", message, 0};
    }

    /**
     * @brief Creates an SfVoiceMediaError representing an HTTP error response.
     *
     * @param status_code HTTP status code from the response (e.g., 404, 500).
     * @param body Response body used as the error message when no JSON error payload is available.
     * @return SfVoiceMediaError Error with `code` set to "http_error", `message` set to `body`, and `status_code` set to `status_code`.
     */
    static SfVoiceMediaError http(int status_code, const std::string& body) {
        return SfVoiceMediaError{"http_error", body, status_code};
    }

    /**
     * @brief Constructs an SfVoiceMediaError for a parse failure (e.g., JSON parse error).
     *
     * @param detail Human-readable detail about the parse failure.
     * @return SfVoiceMediaError Error with `code` set to "parse_error", `message` set to `detail`, and `status_code` set to 0.
     */
    static SfVoiceMediaError parse(const std::string& detail) {
        return SfVoiceMediaError{"parse_error", detail, 0};
    }

    /**
     * @brief Create an error representing a polling timeout for a task.
     *
     * @param task_id Identifier of the task that failed to reach a terminal state.
     * @return SfVoiceMediaError Error with `code` set to `"poll_timeout"`, `message`
     * set to `"task <task_id> did not reach a terminal state before the timeout"`,
     * and `status_code` set to `0`.
     */
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

    /**
         * @brief Constructs an SfVoiceMediaException that wraps the provided SfVoiceMediaError.
         *
         * @param err The error payload to wrap; its contents are moved into the exception and its `message`
         *            is used to initialize the base `std::runtime_error` message.
         */
        explicit SfVoiceMediaException(SfVoiceMediaError err)
        : std::runtime_error(err.message)
        , error(std::move(err)) {}

    /**
         * @brief Construct an SfVoiceMediaException from individual error fields.
         *
         * @param code Machine-readable error code.
         * @param message Human-readable error message used as the exception's diagnostic message.
         * @param status_code HTTP status code associated with the error; 0 when not an HTTP error.
         */
        SfVoiceMediaException(std::string code, std::string message, int status_code = 0)
        : SfVoiceMediaException(SfVoiceMediaError{std::move(code), std::move(message), status_code}) {}
};

} // namespace sf_voice
