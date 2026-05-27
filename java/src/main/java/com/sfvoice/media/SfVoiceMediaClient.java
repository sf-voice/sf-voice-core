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

    /**
     * Constructs an SfVoiceMediaClient from the provided Builder.
     *
     * Normalizes the builder's baseUrl by removing trailing slashes, copies the API key,
     * creates an HttpClient with a 10-second connect timeout, and initializes an
     * ObjectMapper configured to ignore unknown JSON properties.
     *
     * @param builder builder containing configuration values (baseUrl and apiKey)
     */
    private SfVoiceMediaClient(Builder builder) {
        this.baseUrl = builder.baseUrl.replaceAll("/+$", "");
        this.apiKey  = builder.apiKey;
        this.http    = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();
        this.json = new ObjectMapper()
            .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
    }

    /**
     * Create an HttpRequest.Builder targeting the client's API path with standard headers and timeout.
     *
     * @param path the request path appended to the client's baseUrl (baseUrl has no trailing slash); should start with a leading '/'
     * @return an HttpRequest.Builder whose URI is baseUrl + path, with the `X-API-Key` and `Content-Type: application/json` headers set and a 30-second request timeout
     */

    private HttpRequest.Builder baseRequest(String path) {
        return HttpRequest.newBuilder()
            .uri(URI.create(baseUrl + path))
            .header("X-API-Key", apiKey)
            .header("Content-Type", "application/json")
            .timeout(Duration.ofSeconds(30));
    }

    /**
     * Send the given HTTP request, validate the response status, and deserialize the response body.
     *
     * @param request      the HTTP request to send (must include URI, headers and method)
     * @param responseType the class to deserialize a successful JSON response into
     * @return the deserialized response object, or `null` if the server returned 204 No Content
     * @throws SfVoiceMediaException if the response status is not in the 200–299 range; the exception's code and message
     *                               will reflect parsed `error.code` and `error.message` from the response body when present
     * @throws IOException          if an I/O error occurs sending the request or deserializing the response
     * @throws InterruptedException if the thread is interrupted while waiting for the HTTP response
     */
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

    /**
     * Serialize an object to its JSON representation.
     *
     * @param body the object to serialize
     * @return the JSON string representation of the given object
     * @throws RuntimeException if serialization fails
     */
    private String toJson(Object body) {
        try {
            return json.writeValueAsString(body);
        } catch (IOException e) {
            throw new RuntimeException("failed to serialise request body", e);
        }
    }

    // ── public API ────────────────────────────────────────────────────────

    /**
     * Submit a media file for ingestion and receive a task to track its processing.
     *
     * @param request the ingestion request payload containing the media reference and options
     * @return an IngestResponse containing the created task ID and related ingestion metadata
     * @throws SfVoiceMediaException if the API responds with an error status
     * @throws IOException if an I/O error occurs sending the request or reading the response
     * @throws InterruptedException if the operation is interrupted while waiting for the HTTP response
     */
    public IngestResponse ingest(IngestRequest request)
            throws SfVoiceMediaException, IOException, InterruptedException {

        HttpRequest req = baseRequest("/v1/ingest")
            .POST(HttpRequest.BodyPublishers.ofString(toJson(request)))
            .build();
        return execute(req, IngestResponse.class);
    }

    /**
     * Fetches the current state of an ingestion task.
     *
     * @param taskId the identifier of the task to retrieve
     * @return the Task representing the task's current state
     * @throws SfVoiceMediaException if the API returns an error (non-2xx) — contains error code, message, and HTTP status
     * @throws IOException if a network or JSON I/O error occurs
     * @throws InterruptedException if the calling thread is interrupted while sending the request
     */
    public Task getTask(String taskId)
            throws SfVoiceMediaException, IOException, InterruptedException {

        HttpRequest req = baseRequest("/v1/tasks/" + taskId)
            .GET()
            .build();
        return execute(req, Task.class);
    }

    /**
     * Retrieve a paginated list of assets.
     *
     * @param page  page number to retrieve (1-based)
     * @param limit maximum number of assets to return on the page
     * @return the assets and pagination metadata for the requested page
     * @throws SfVoiceMediaException if the API returns an error response
     * @throws IOException if an I/O error occurs while sending the request
     * @throws InterruptedException if the thread is interrupted while waiting for the response
     */
    public AssetListResponse listAssets(int page, int limit)
            throws SfVoiceMediaException, IOException, InterruptedException {

        HttpRequest req = baseRequest("/v1/assets?page=" + page + "&limit=" + limit)
            .GET()
            .build();
        return execute(req, AssetListResponse.class);
    }

    /**
     * Retrieve a page of assets using the server's default pagination (page=1, limit=20).
     *
     * @return the AssetListResponse containing assets for the default page and limit
     * @throws SfVoiceMediaException if the API responds with an error status
     * @throws IOException if an I/O error occurs while sending the request
     * @throws InterruptedException if the operation is interrupted while waiting for a response
     */
    public AssetListResponse listAssets()
            throws SfVoiceMediaException, IOException, InterruptedException {
        return listAssets(1, 20);
    }

    /**
     * Retrieve an asset by its ID.
     *
     * @param assetId the asset identifier
     * @return the Asset corresponding to the given assetId
     * @throws SfVoiceMediaException if the API returns a non-2xx HTTP status
     * @throws IOException if an I/O error occurs while sending the request or reading the response
     * @throws InterruptedException if the thread is interrupted while waiting for the HTTP response
     */
    public Asset getAsset(String assetId)
            throws SfVoiceMediaException, IOException, InterruptedException {

        HttpRequest req = baseRequest("/v1/assets/" + assetId)
            .GET()
            .build();
        return execute(req, Asset.class);
    }

    /**
     * Soft-delete the asset with the given ID; completes when the server acknowledges deletion.
     *
     * The backend retains the record but excludes it from list results. The call completes
     * when the server returns HTTP 204.
     *
     * @param assetId the ID of the asset to soft-delete
     * @throws SfVoiceMediaException if the server responds with an error status
     * @throws IOException if an I/O error occurs sending the request or reading the response
     * @throws InterruptedException if the calling thread is interrupted while sending the request
     */
    public void deleteAsset(String assetId)
            throws SfVoiceMediaException, IOException, InterruptedException {

        HttpRequest req = baseRequest("/v1/assets/" + assetId)
            .DELETE()
            .build();
        execute(req, Void.class);
    }

    /**
     * Performs a semantic search over indexed media using the provided search parameters.
     *
     * @param request the search request describing the query and any search options
     * @return the search results and associated metadata
     * @throws SfVoiceMediaException if the API responds with an error status or error payload
     * @throws IOException if a network or I/O error occurs while sending the request or reading the response
     * @throws InterruptedException if the thread is interrupted while sending the HTTP request
     */
    public SearchResponse search(SearchRequest request)
            throws SfVoiceMediaException, IOException, InterruptedException {

        HttpRequest req = baseRequest("/v1/search")
            .POST(HttpRequest.BodyPublishers.ofString(toJson(request)))
            .build();
        return execute(req, SearchResponse.class);
    }

    /**
     * Waits until the specified task reaches a terminal state.
     *
     * Polls the task state at up to `intervalMs` millisecond intervals until the task is terminal
     * or `timeoutMs` milliseconds have elapsed.
     *
     * @param taskId     the identifier of the task to poll
     * @param intervalMs poll interval in milliseconds between successive checks
     * @param timeoutMs  maximum total time in milliseconds to wait before giving up
     * @return the final {@link Task} when it reaches a terminal state
     * @throws SfVoiceMediaException if the task does not reach a terminal state before the timeout
     * @throws IOException if fetching the task state fails due to I/O or response parsing errors
     * @throws InterruptedException if the thread is interrupted while sleeping between polls
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

        /**
 * Sets the API key used for authentication in requests (sent as the `X-API-Key` header).
 *
 * @param apiKey the API key value; must be non-null and not blank when building the client
 * @return this Builder instance
 */
public Builder apiKey(String apiKey)   { this.apiKey = apiKey; return this; }
        /**
 * Sets the API base URL the client will use.
 *
 * The URL should be a full URL including scheme (for example, "https://api.sf-voice.com"); trailing slashes will be normalized by the client constructor.
 *
 * @param baseUrl the base URL for API requests
 * @return this builder
 */
public Builder baseUrl(String baseUrl) { this.baseUrl = baseUrl; return this; }

        /**
         * Builds an SfVoiceMediaClient configured with the values in this Builder.
         *
         * @return a new SfVoiceMediaClient configured with this Builder
         * @throws IllegalStateException if the required `apiKey` is null or blank
         */
        public SfVoiceMediaClient build() {
            if (apiKey == null || apiKey.isBlank()) {
                throw new IllegalStateException("apiKey must be set");
            }
            return new SfVoiceMediaClient(this);
        }
    }
}
