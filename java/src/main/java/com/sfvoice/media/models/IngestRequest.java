package com.sfvoice.media.models;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.Map;

@JsonInclude(JsonInclude.Include.NON_NULL)
public class IngestRequest {

    private final String source;
    private final String url;
    @JsonProperty("s3_key")
    private final String s3Key;
    @JsonProperty("media_type")
    private final String mediaType;
    private final Map<String, String> metadata;

    private IngestRequest(Builder builder) {
        this.source    = builder.source;
        this.url       = builder.url;
        this.s3Key     = builder.s3Key;
        this.mediaType = builder.mediaType;
        this.metadata  = builder.metadata;
    }

    public String getSource()                { return source; }
    public String getUrl()                   { return url; }
    public String getS3Key()                 { return s3Key; }
    public String getMediaType()             { return mediaType; }
    public Map<String, String> getMetadata() { return metadata; }

    public static Builder fromUrl(String url) {
        return new Builder("url").url(url);
    }

    public static Builder fromS3(String s3Key) {
        return new Builder("s3").s3Key(s3Key);
    }

    public static class Builder {
        private final String source;
        private String url;
        private String s3Key;
        private String mediaType;
        private Map<String, String> metadata;

        private Builder(String source) { this.source = source; }

        public Builder url(String url)                          { this.url = url; return this; }
        public Builder s3Key(String s3Key)                      { this.s3Key = s3Key; return this; }
        public Builder mediaType(String mediaType)              { this.mediaType = mediaType; return this; }
        public Builder metadata(Map<String, String> metadata)   { this.metadata = metadata; return this; }

        public IngestRequest build() { return new IngestRequest(this); }
    }
}
