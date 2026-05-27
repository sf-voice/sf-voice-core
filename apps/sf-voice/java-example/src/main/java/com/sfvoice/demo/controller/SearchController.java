package sh.sf-voice.demo.controller;

import com.sfvoice.media.SfVoiceMediaClient;
import com.sfvoice.media.SfVoiceMediaException;
import com.sfvoice.media.models.AssetListResponse;
import com.sfvoice.media.models.SearchRequest;
import com.sfvoice.media.models.SearchResponse;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

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
     * @param dto the deserialized and validated request body
     * @return 200 OK with the SearchResponse on success; 400 Bad Request when validation
     *         fails (e.g. query is blank); the HTTP status from SfVoiceMediaException with
     *         body {"error":{"code":..., "message":...}} when that exception is thrown;
     *         500 Internal Server Error with {"error": "<message>"} for other unexpected errors
     */
    @PostMapping("/search")
    public ResponseEntity<?> search(@Valid @RequestBody SearchRequestDto dto) {
        try {
            SearchRequest.Builder builder = SearchRequest.query(dto.getQuery());
            if (dto.getTypes() != null)    builder.types(dto.getTypes());
            if (dto.getAssetIds() != null) builder.assetIds(dto.getAssetIds());
            if (dto.getThreshold() != null) builder.threshold(dto.getThreshold());
            if (dto.getPage() != null)      builder.page(dto.getPage());
            if (dto.getLimit() != null)     builder.limit(dto.getLimit());

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
