package com.sfvoice.media.models;

import com.fasterxml.jackson.annotation.JsonProperty;

public class SearchResult {

    @JsonProperty("asset_id")      private String assetId;
    private float score;
    @JsonProperty("start_ms")      private long startMs;
    @JsonProperty("end_ms")        private long endMs;
    @JsonProperty("match_type")    private String matchType;
    @JsonProperty("thumbnail_url") private String thumbnailUrl;

    public String getAssetId()      { return assetId; }
    public float getScore()         { return score; }
    public long getStartMs()        { return startMs; }
    public long getEndMs()          { return endMs; }
    public String getMatchType()    { return matchType; }
    public String getThumbnailUrl() { return thumbnailUrl; }
}
