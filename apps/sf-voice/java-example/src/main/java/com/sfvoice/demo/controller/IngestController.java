package sh.sfvoice.demo.controller;

import sh.sfvoice.media.SfVoiceMediaClient;
import sh.sfvoice.media.SfVoiceMediaException;
import sh.sfvoice.media.models.IngestRequest;
import sh.sfvoice.media.models.IngestResponse;
import sh.sfvoice.media.models.Task;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
public class IngestController {

    private final SfVoiceMediaClient client;

    /**
     * Creates an IngestController that handles media ingest and task status endpoints.
     *
     * @param client the SfVoiceMediaClient used to call external media ingestion and task APIs
     */
    public IngestController(SfVoiceMediaClient client) {
        this.client = client;
    }

    /**
     * Create an ingest job for a media URL and return ingest identifiers and status.
     *
     * <p>Expects a JSON body with a required "url" and an optional "media_type".</p>
     *
     * @param body a map containing request fields; must include "url" (string). May include "media_type" (string).
     * @return a ResponseEntity containing:
     *         - 202 Accepted with an IngestResponse on success (contains asset_id, task_id, status),
     *         - 400 Bad Request with {"error": "url is required"} if "url" is missing or blank,
     *         - {status from SfVoiceMediaException} with {"error": {"code": <code>, "message": <message>}} when SfVoiceMediaException is thrown,
     *         - 500 Internal Server Error with {"error": <message>} for other failures.
     */
    @PostMapping("/ingest")
    public ResponseEntity<?> ingest(@RequestBody Map<String, String> body) {
        String url = body.get("url");
        if (url == null || url.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "url is required"));
        }
        String mediaType = body.get("media_type");
        if (mediaType != null && !mediaType.isBlank()
                && !mediaType.equals("video") && !mediaType.equals("audio")) {
            return ResponseEntity.badRequest().body(Map.of("error", "media_type must be video or audio"));
        }

        try {
            IngestRequest req = IngestRequest.fromUrl(url)
                    .mediaType(mediaType)
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
     * Retrieve current status and details for an ingest task.
     *
     * If successful, returns the Task for the given task identifier.
     * If an SfVoiceMediaException is thrown, returns a response with the exception's HTTP status
     * and a body of the form {"error": {"code": <code>, "message": <message>}}.
     * For other exceptions, returns 500 with a body of the form {"error": "<message>"}.
     *
     * @param id the ingest task identifier
     * @return a ResponseEntity containing the Task on success or an error payload on failure
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
