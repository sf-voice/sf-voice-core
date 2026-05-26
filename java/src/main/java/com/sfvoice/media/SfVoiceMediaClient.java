package com.sfvoice.media;

import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sfvoice.media.models.*;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

/**
 * blocking HTTP client for the sf-voice media API.
 *
 * <pre>{@code
 * SfVoiceMediaClient client = new SfVoiceMediaClient.Builder()
 *     .apiKey(System.getenv("SF_VOICE_API_KEY"))
 *     .baseUrl("https://api.sf-voice.com")
 *     .build();
 * }</pre>
 */
public class SfVoiceMediaClient {

    private final String baseUrl;
    private final String apiKey;
    private final HttpClient http;
    private final ObjectMapper json;

    private SfVoiceMediaClient(Builder builder) {
        this.baseUrl = builder.baseUrl.replaceAll("/+$", "");
        this.apiKey  = builder.apiKey;
        this.http    = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();
        this.json = new ObjectMapper()
            .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
    }

    // ── internal helpers ──────────────────────────────────────────────────

    private HttpRequest.Builder baseRequest(String path) {
        return HttpRequest.newBuilder()
            .uri(URI.create(baseUrl + path))
            .header("X-API-Key", apiKey)
            .header("Content-Type", "application/json")
            .timeout(Duration.ofSeconds(30));
    }

    private <T> T execute(HttpRequest request, Class<T> responseType)
            throws SfVoiceMediaException, IOException, InterruptedException {

        HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() == 204) {
            return null;
        }

        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            String code    = "http_error";
            String message = "request failed with status " + response.statusCode();
            try {
                var node = json.readTree(response.body());
                var err  = node.path("error");
                if (!err.isMissingNode()) {
                    code    = err.path("code").asText(code);
                    message = err.path("message").asText(message);
                }
            } catch (Exception ignored) {}
            throw new SfVoiceMediaException(code, message, response.statusCode());
        }

        return json.readValue(response.body(), responseType);
    }

    private String toJson(Object body) {
        try {
            return json.writeValueAsString(body);
        } catch (IOException e) {
            throw new RuntimeException("failed to serialise request body", e);
        }
    }

    // ── public API ────────────────────────────────────────────────────────

    /**
     * submit a media file for ingestion. returns immediately with a task_id
     * you can poll with {@link #getTask(String)} or {@link #pollTask(String, long, long)}.
     */
    public IngestResponse ingest(IngestRequest request)
            throws SfVoiceMediaException, IOException, InterruptedException {

        HttpRequest req = baseRequest("/v1/ingest")
            .POST(HttpRequest.BodyPublishers.ofString(toJson(request)))
            .build();
        return execute(req, IngestResponse.class);
    }

    /** fetch the current state of an ingestion task. */
    public Task getTask(String taskId)
            throws SfVoiceMediaException, IOException, InterruptedException {

        HttpRequest req = baseRequest("/v1/tasks/" + taskId)
            .GET()
            .build();
        return execute(req, Task.class);
    }

    /** list assets with pagination. */
    public AssetListResponse listAssets(int page, int limit)
            throws SfVoiceMediaException, IOException, InterruptedException {

        HttpRequest req = baseRequest("/v1/assets?page=" + page + "&limit=" + limit)
            .GET()
            .build();
        return execute(req, AssetListResponse.class);
    }

    /** list assets with server defaults (page=1, limit=20). */
    public AssetListResponse listAssets()
            throws SfVoiceMediaException, IOException, InterruptedException {
        return listAssets(1, 20);
    }

    /** fetch a single asset by ID. */
    public Asset getAsset(String assetId)
            throws SfVoiceMediaException, IOException, InterruptedException {

        HttpRequest req = baseRequest("/v1/assets/" + assetId)
            .GET()
            .build();
        return execute(req, Asset.class);
    }

    /**
     * soft-delete an asset. the backend retains the record but excludes it
     * from list results. returns when HTTP 204 is received.
     */
    public void deleteAsset(String assetId)
            throws SfVoiceMediaException, IOException, InterruptedException {

        HttpRequest req = baseRequest("/v1/assets/" + assetId)
            .DELETE()
            .build();
        execute(req, Void.class);
    }

    /** run a semantic search across indexed media. */
    public SearchResponse search(SearchRequest request)
            throws SfVoiceMediaException, IOException, InterruptedException {

        HttpRequest req = baseRequest("/v1/search")
            .POST(HttpRequest.BodyPublishers.ofString(toJson(request)))
            .build();
        return execute(req, SearchResponse.class);
    }

    /**
     * block until the task reaches a terminal state, then return the final {@link Task}.
     *
     * @param taskId      the task to poll.
     * @param intervalMs  milliseconds between polls (default 1500).
     * @param timeoutMs   max total wait time in ms (default 120_000).
     * @throws InterruptedException if the thread is interrupted while sleeping.
     */
    public Task pollTask(String taskId, long intervalMs, long timeoutMs)
            throws SfVoiceMediaException, IOException, InterruptedException {

        long deadline = System.currentTimeMillis() + timeoutMs;

        while (true) {
            Task task = getTask(taskId);
            if (task.isTerminal()) return task;

            long remaining = deadline - System.currentTimeMillis();
            if (remaining <= 0) {
                throw new SfVoiceMediaException(
                    "poll_timeout",
                    "task " + taskId + " did not complete within " + timeoutMs + "ms",
                    0
                );
            }
            Thread.sleep(Math.min(intervalMs, remaining));
        }
    }

    // ── builder ───────────────────────────────────────────────────────────

    public static class Builder {
        private String apiKey;
        private String baseUrl = "https://api.sf-voice.com";

        public Builder apiKey(String apiKey)   { this.apiKey = apiKey; return this; }
        public Builder baseUrl(String baseUrl) { this.baseUrl = baseUrl; return this; }

        public SfVoiceMediaClient build() {
            if (apiKey == null || apiKey.isBlank()) {
                throw new IllegalStateException("apiKey must be set");
            }
            return new SfVoiceMediaClient(this);
        }
    }
}
