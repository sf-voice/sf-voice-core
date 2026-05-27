# sf_voice C++ SDK

Header-only C++17 SDK for the sf-voice media API.

Version: `0.1.1`

## Installation

With Conan:

```txt
requires = "sf_voice/0.1.1"
```

With CMake from this repo:

```cmake
add_subdirectory(path/to/sf-voice-core/cpp sf_voice_build)
target_link_libraries(your_target PRIVATE sf_voice::sf_voice)
```

The SDK depends on `nlohmann_json` and `cpr`. CMake can fetch missing
dependencies with `SF_VOICE_FETCH_DEPS=ON`, or you can install them locally.

For local development in this repo:

```sh
cmake -S . -B build -DSF_VOICE_FETCH_DEPS=ON -DSF_VOICE_INSTALL=OFF
cmake --build build
```

Use `SF_VOICE_INSTALL=OFF` when configuring directly with fetched dependencies.

## Usage

```cpp
#include <cstdlib>
#include <iostream>

#include <sf_voice/sf_voice.hpp>

int main() {
    sf_voice::SfVoiceMedia client(std::getenv("SF_VOICE_API_KEY"));

    sf_voice::IngestRequest ingest_request;
    ingest_request.url = "https://example.com/recording.mp4";
    ingest_request.extra = {
        {"media_type", "video"},
        {"metadata", {{"title", "product demo"}}}
    };

    auto ingest = client.ingest(ingest_request).get();
    if (!ingest.ok) {
        std::cerr << ingest.error.code << ": " << ingest.error.message << "\n";
        return 1;
    }

    auto task = client.poll_task(ingest.value.task_id).get();
    if (!task.ok) {
        std::cerr << task.error.code << ": " << task.error.message << "\n";
        return 1;
    }

    sf_voice::SearchRequest search_request;
    search_request.query = "product launch";
    search_request.type = sf_voice::SearchType::Conversation;

    auto search = client.search(search_request).get();
    if (!search.ok) {
        std::cerr << search.error.code << ": " << search.error.message << "\n";
        return 1;
    }

    std::cout << search.value.results.size() << "\n";
}
```

## API

The client exposes async methods that return `std::future<Result<T>>`:

- `ingest(request)` - submit URL or S3 media for indexing.
- `get_task(task_id)` - fetch task state.
- `poll_task(task_id, interval, timeout)` - wait until a task is terminal.
- `list_assets(request)` - list indexed assets.
- `get_asset(asset_id)` - fetch one asset.
- `delete_asset(asset_id)` - soft-delete an asset.
- `search(request)` - search indexed media with natural language.

## Examples

- [`../apps/chips`](../apps/chips) - CMake CLI demo.

