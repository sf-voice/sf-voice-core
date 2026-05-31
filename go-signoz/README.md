# sf-voice-signoz-go

Zero-dependency Go SDK that ships **CPU profiles** and **CPU-utilization
metrics** to SigNoz, so SigNoz can flame-graph hot paths and fire a **Slack
alert when CPU is high**.

```
import signoz "github.com/sf-voice/sf-voice-signoz-go"
```

## What it does

Two independent background loops, started by one call:

| Loop | Mechanism | Goes to | Answers |
|------|-----------|---------|---------|
| **Metrics** | samples process CPU via `getrusage`, exports OTLP/HTTP JSON | SigNoz collector `/v1/metrics` | *Is CPU high?* — the timeseries an alert fires on |
| **Profiler** | continuous `runtime/pprof` CPU profiles, Pyroscope pprof push | `/ingest` endpoint | *Where is the CPU going?* — flame graphs |

> **The SDK never talks to Slack.** A flame graph can't be threshold-alerted,
> so the metric is what makes "Slack on high CPU" possible. The Slack message
> itself is a **SigNoz alert rule + Slack notification channel** (steps below).

## Usage

```go
agent, err := signoz.Start(signoz.Config{
    ServiceName:     "sf-voice-api",
    MetricsEndpoint: "https://ingest.us.signoz.cloud:443",     // or http://localhost:4318
    MetricsHeaders:  map[string]string{"signoz-ingestion-key": os.Getenv("SIGNOZ_KEY")},

    ProfilesEndpoint:  "http://localhost:4040",                // Pyroscope / SigNoz profiling ingest
    ProfilesAuthToken: os.Getenv("PYROSCOPE_TOKEN"),           // optional, sent as Bearer

    Labels: map[string]string{"env": "prod", "region": "sfo"}, // attached to metrics + profiles
})
if err != nil {
    log.Fatal(err)
}
defer agent.Stop()
```

Either endpoint may be omitted to disable that loop; at least one is required.
Defaults: `MetricsInterval` 15s, `ProfileInterval` 10s, 30s HTTP timeout,
`log.Default()` for non-fatal upload errors.

A runnable demo (burns a core so the metric climbs) lives in `./example`.

## Metrics emitted

| OTLP name | In SigNoz (dots → underscores) | Type | Meaning |
|-----------|-------------------------------|------|---------|
| `process.cpu.utilization` | `process_cpu_utilization` | gauge, `[0,1]` | 1.0 = every core saturated (`ΔCPU / (Δwall · nCPU)`) |
| `process.runtime.go.goroutines` | `process_runtime_go_goroutines` | gauge | live goroutine count |

## Wiring "high CPU → Slack" in SigNoz (config, not code)

1. **Point metrics at SigNoz.** Self-host: `MetricsEndpoint=http://<collector>:4318`.
   Cloud: the regional ingest URL + `signoz-ingestion-key` header (shown above).
2. **Confirm the metric.** SigNoz → *Metrics* and search `process_cpu_utilization`.
3. **Create the alert.** *Alerts → New Alert → Metrics-based*:
   - Metric `process_cpu_utilization`, aggregation **avg** (or `p95`), grouped by `host_name`.
   - Condition: **above `0.85` for 5m** (utilization is `0–1`, so `0.85` = 85%).
4. **Add a Slack channel.** *Settings → Alert Channels → New → Slack*, paste an
   [incoming webhook](https://api.slack.com/messaging/webhooks) URL, pick the channel.
5. **Attach** the channel to the alert. SigNoz now posts to Slack whenever CPU
   stays above your threshold.

## Profiling target

The profiler speaks the **Pyroscope pprof ingest** protocol (`POST /ingest` with
a multipart `profile` field; `name`/`from`/`until`/`format=pprof`/`sampleRate`/
`spyName=gospy` as query params). Point `ProfilesEndpoint` at a Pyroscope server,
or at SigNoz's profiling ingest if your deployment exposes one.

> **Heads-up:** as of this writing SigNoz's Pyroscope-compatible profiling
> ingest is not a stable, documented endpoint
> ([SigNoz#5641](https://github.com/SigNoz/signoz/issues/5641)). The profiler
> works today against Pyroscope; the **metric → Slack alert** path is the part
> that runs entirely on SigNoz's supported OTLP + alerting stack. Leave
> `ProfilesEndpoint` empty to run metrics-only.

## Platform support

Process CPU sampling uses `getrusage(RUSAGE_SELF)` (Linux + macOS, `//go:build
unix`). On other platforms the metrics loop logs an unsupported-platform error
once and the profiler loop still runs. The module has **no third-party
dependencies**.
