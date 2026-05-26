package com.sfvoice.demo.controller;

import com.sfvoice.media.SfVoiceMediaClient;
import com.sfvoice.media.SfVoiceMediaException;
import com.sfvoice.media.models.AssetListResponse;
import com.sfvoice.media.models.SearchRequest;
import com.sfvoice.media.models.SearchResponse;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
public class SearchController {

    private final SfVoiceMediaClient client;

    /**
     * Create a SearchController backed by the provided SfVoiceMediaClient.
     */
    public SearchController(SfVoiceMediaClient client) {
        this.client = client;
    }

    /**
     * Handle POST /search requests: validate the request body, construct a SearchRequest,
     * invoke the media client, and return the search results.
     *
     * Expected request body keys:
     * - "query" (String) — required; the search query.
     * - "types" (List<String>) — optional; asset types to filter by.
     * - "asset_ids" (List<String>) — optional; specific asset IDs to restrict the search.
     *
     * @param body the parsed JSON request body containing the keys described above
     * @return 200 OK with the SearchResponse on success; 400 Bad Request with
     *         {"error":"query is required"} when "query" is missing or blank; the HTTP
     *         status from SfVoiceMediaException with body {"error":{"code":..., "message":...}}
     *         when that exception is thrown; 500 Internal Server Error with
     *         {"error": "<message>"} for other unexpected errors
     */
    @PostMapping("/search")
    public ResponseEntity<?> search(@RequestBody Map<String, Object> body) {
        String query = (String) body.get("query");
        if (query == null || query.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "query is required"));
        }

        try {
            @SuppressWarnings("unchecked")
            List<String> types = (List<String>) body.get("types");
            @SuppressWarnings("unchecked")
            List<String> assetIds = (List<String>) body.get("asset_ids");

            SearchRequest.Builder builder = SearchRequest.query(query);
            if (types != null)    builder.types(types);
            if (assetIds != null) builder.assetIds(assetIds);

            SearchResponse resp = client.search(builder.build());
            return ResponseEntity.ok(resp);
        } catch (SfVoiceMediaException e) {
            return ResponseEntity.status(e.getStatus()).body(
                    Map.of("error", Map.of("code", e.getCode(), "message", e.getMessage()))
            );
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Retrieve a paginated list of assets.
     *
     * @param page  the page number to retrieve, starting at 1
     * @param limit the maximum number of assets per page
     * @return an HTTP response containing either:
     *         - an AssetListResponse on success,
     *         - an error object with keys `code` and `message` and the HTTP status from SfVoiceMediaException when a SfVoiceMediaException is thrown,
     *         - or an error object with the exception message and HTTP 500 for other exceptions
     */
    @GetMapping("/assets")
    public ResponseEntity<?> listAssets(
            @RequestParam(defaultValue = "1")  int page,
            @RequestParam(defaultValue = "20") int limit) {
        try {
            AssetListResponse resp = client.listAssets(page, limit);
            return ResponseEntity.ok(resp);
        } catch (SfVoiceMediaException e) {
            return ResponseEntity.status(e.getStatus()).body(
                    Map.of("error", Map.of("code", e.getCode(), "message", e.getMessage()))
            );
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }
}
