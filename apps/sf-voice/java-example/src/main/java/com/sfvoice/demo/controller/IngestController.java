package com.sfvoice.demo.controller;

import com.sfvoice.media.SfVoiceMediaClient;
import com.sfvoice.media.SfVoiceMediaException;
import com.sfvoice.media.models.IngestRequest;
import com.sfvoice.media.models.IngestResponse;
import com.sfvoice.media.models.Task;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
public class IngestController {

    private final SfVoiceMediaClient client;

    public IngestController(SfVoiceMediaClient client) {
        this.client = client;
    }

    /**
     * POST /ingest
     * body: { "url": "https://...", "media_type": "video" }
     * returns 202 with { asset_id, task_id, status }
     */
    @PostMapping("/ingest")
    public ResponseEntity<?> ingest(@RequestBody Map<String, String> body) {
        String url = body.get("url");
        if (url == null || url.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "url is required"));
        }

        try {
            IngestRequest req = IngestRequest.fromUrl(url)
                    .mediaType(body.getOrDefault("media_type", null))
                    .build();
            IngestResponse resp = client.ingest(req);
            return ResponseEntity.accepted().body(resp);
        } catch (SfVoiceMediaException e) {
            return ResponseEntity.status(e.getStatus()).body(
                    Map.of("error", Map.of("code", e.getCode(), "message", e.getMessage()))
            );
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * GET /task/{id}
     * returns current task status
     */
    @GetMapping("/task/{id}")
    public ResponseEntity<?> getTask(@PathVariable String id) {
        try {
            Task task = client.getTask(id);
            return ResponseEntity.ok(task);
        } catch (SfVoiceMediaException e) {
            return ResponseEntity.status(e.getStatus()).body(
                    Map.of("error", Map.of("code", e.getCode(), "message", e.getMessage()))
            );
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }
}
