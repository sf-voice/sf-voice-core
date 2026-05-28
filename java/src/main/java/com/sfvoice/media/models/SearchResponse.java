package com.sfvoice.media.models;

import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.List;

public class SearchResponse {

    private List<SearchResult> results;
    @JsonProperty("page_info") private PageInfo pageInfo;

    public List<SearchResult> getResults() { return results; }
    public PageInfo getPageInfo()          { return pageInfo; }
}
