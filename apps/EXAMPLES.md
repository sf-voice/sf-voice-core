# apps examples

Small examples for exercising the sf-voice SDKs and prototypes.

| app | stack | purpose | smoke check |
| --- | --- | --- | --- |
| `livecart` | Go | CLI ingest, poll, search, assets | `go test ./...` |
| `fifteenlabs` | TypeScript/Fastify | browser ingest/search demo | `bun run typecheck` |
| `cohere` | Python | sync/async SDK CLI demo | `python3 -m compileall -q sf_voice_py` |
| `chips` | C++/CMake | C++ SDK CLI demo | `cmake -S . -B build` |
| `sf-voice` | Java/Kotlin | REST proxy examples | `gradle :java-example:compileJava` |
| `fraud-prototype` | TypeScript/Fastify | phone-line fraud prototype | `bun run typecheck` |

Most examples call external APIs only when you run their demo command with real
credentials. Smoke checks should stay local unless the language toolchain needs
to download dependencies on first use.
