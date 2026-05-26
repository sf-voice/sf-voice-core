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

    public SearchController(SfVoiceMediaClient client) {
        this.client = client;
    }

    /**
     * POST /search
     * body: { "query": "...", "types": ["visual"], "threshold": 0.7 }
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
     * GET /assets?page=1&limit=20
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
