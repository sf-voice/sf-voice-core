# sf-voice C++ example

CMake CLI demo for the C++ SDK.

## setup

```bash
cp .env.example .env
# fill in SF_VOICE_API_KEY
```

## NOTE

The first CMake configure may need network access to fetch `nlohmann_json` and
`cpr` unless those packages are already installed and discoverable by CMake.

With network access:

```bash
cmake -S . -B build -DSF_VOICE_FETCH_DEPS=ON -DSF_VOICE_INSTALL=OFF
cmake --build build
```

With local Homebrew dependencies:

```bash
brew install nlohmann-json cpr
cmake -S . -B build -DSF_VOICE_FETCH_DEPS=OFF -DSF_VOICE_INSTALL=OFF
cmake --build build
```

Use `SF_VOICE_INSTALL=OFF` for this example app. The SDK install/export rules
can fail when dependencies are pulled by `FetchContent`, because install exports
expect every linked target to belong to an export set.

## smoke check

```bash
cmake -S . -B build
cmake --build build
```

## run

```bash
set -a; source .env; set +a
./build/chips_example "https://example.com/recording.mp4" "product launch"
```
