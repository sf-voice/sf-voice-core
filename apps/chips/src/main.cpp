/**
 * sf-voice media SDK demo — C++ CLI.
 *
 * Usage:
 *   ./krisp_demo <media-url> "<search-query>"
 *
 * Demonstrates the Result<T> error-handling pattern and async SDK calls
 * in the style of a C++ systems application (e.g. Krisp's noise-cancellation
 * pipeline reading from a media library).
 */

#include <chrono>
#include <cstdlib>
#include <iostream>
#include <string>
#include <thread>

#include "sf_voice/sf_voice.hpp"

using namespace sf_voice;

// load and validate required env vars
static std::string env_required(const char* name) {
    const char* v = std::getenv(name);
    if (!v || v[0] == '\0') {
        std::cerr << "error: required env var missing: " << name << "\n";
        std::exit(1);
    }
    return v;
}

static std::string env_optional(const char* name, const char* fallback) {
    const char* v = std::getenv(name);
    return (v && v[0] != '\0') ? v : fallback;
}

// pretty-print milliseconds as m:ss
static std::string ms_to_time(uint64_t ms) {
    uint64_t s = ms / 1000;
    char buf[16];
    std::snprintf(buf, sizeof(buf), "%llu:%02llu", (unsigned long long)(s / 60), (unsigned long long)(s % 60));
    return buf;
}

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "usage: krisp_demo <media-url> \"<search-query>\"\n";
        return 2;
    }

    std::string media_url = argv[1];
    std::string query     = argv[2];

    const std::string api_key  = env_required("SF_VOICE_API_KEY");
    const std::string base_url = env_optional("SF_VOICE_BASE_URL", "https://api.sf-voice.com");

    SfVoiceMedia client(api_key, base_url);

    // ── ingest ────────────────────────────────────────────────────────────
    std::cout << "ingesting " << media_url << " …\n";

    IngestRequest ingest_req;
    ingest_req.url = media_url;

    auto ingest_result = client.ingest(ingest_req).get();
    if (!ingest_result.ok) {
        std::cerr << "✗ ingest failed: " << ingest_result.error.message << "\n";
        return 1;
    }

    const auto& ingest_resp = ingest_result.value;
    std::cout << "✓ submitted  asset_id=" << ingest_resp.asset_id
              << "  task_id=" << ingest_resp.task_id << "\n";

    // ── poll ──────────────────────────────────────────────────────────────
    std::cout << "⏳ polling ";
    std::cout.flush();

    auto t0 = std::chrono::steady_clock::now();

    auto poll_result = client.poll_task(
        ingest_resp.task_id,
        std::chrono::milliseconds(1500),
        std::chrono::milliseconds(300'000)
    ).get();

    auto elapsed_s = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    std::cout << "\r";

    if (!poll_result.ok) {
        std::cerr << "✗ polling failed: " << poll_result.error.message << "\n";
        return 1;
    }

    const auto& task = poll_result.value;
    if (task.status == TaskStatus::Failed) {
        std::cerr << "✗ indexing failed: " << task.error.value_or("") << "\n";
        return 1;
    }

    std::cout << "✓ ready  (" << elapsed_s << "s)\n\n";

    // ── search ────────────────────────────────────────────────────────────
    std::cout << "🔍 searching: \"" << query << "\"\n";

    SearchRequest search_req;
    search_req.query = query;
    search_req.asset_id = ingest_resp.asset_id;

    auto search_result = client.search(search_req).get();
    if (!search_result.ok) {
        std::cerr << "✗ search failed: " << search_result.error.message << "\n";
        return 1;
    }

    const auto& resp = search_result.value;
    if (resp.results.empty()) {
        std::cout << "  (no results)\n";
        return 0;
    }

    for (size_t i = 0; i < resp.results.size(); ++i) {
        const auto& r = resp.results[i];
        auto start = ms_to_time(static_cast<uint64_t>(r.start_ms.value_or(0.0)));
        auto end   = ms_to_time(static_cast<uint64_t>(r.end_ms.value_or(0.0)));
        std::cout << "  " << (i + 1) << ". score=" << r.score.value_or(0.0)
                  << "  " << start << "–" << end << "\n";
    }

    return 0;
}
