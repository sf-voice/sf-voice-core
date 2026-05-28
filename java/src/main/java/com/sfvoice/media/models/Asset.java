package com.sfvoice.media.models;

import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.Map;

public class Asset {

    private String id;
    private String status;
    @JsonProperty("media_type")  private String mediaType;
    @JsonProperty("source_type") private String sourceType;
    private Map<String, String> metadata;
    @JsonProperty("duration_ms") private Long durationMs;
    @JsonProperty("created_at")  private String createdAt;
    @JsonProperty("updated_at")  private String updatedAt;

    public String getId()                    { return id; }
    public String getStatus()                { return status; }
    public String getMediaType()             { return mediaType; }
    public String getSourceType()            { return sourceType; }
    public Map<String, String> getMetadata() { return metadata; }
    public Long getDurationMs()              { return durationMs; }
    public String getCreatedAt()             { return createdAt; }
    public String getUpdatedAt()             { return updatedAt; }
}
