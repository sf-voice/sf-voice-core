package sh.sf-voice.demo.controller;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;

import java.util.List;

public class SearchRequestDto {

    @NotBlank(message = "query is required")
    private String query;

    private List<String> types;

    @JsonProperty("asset_ids")
    private List<String> assetIds;

    @DecimalMin("0.0")
    @DecimalMax("1.0")
    private Double threshold;

    @Min(1)
    private Integer page;

    @Min(1)
    private Integer limit;

    public String getQuery() { return query; }
    public void setQuery(String query) { this.query = query; }

    public List<String> getTypes() { return types; }
    public void setTypes(List<String> types) { this.types = types; }

    public List<String> getAssetIds() { return assetIds; }
    public void setAssetIds(List<String> assetIds) { this.assetIds = assetIds; }

    public Double getThreshold() { return threshold; }
    public void setThreshold(Double threshold) { this.threshold = threshold; }

    public Integer getPage() { return page; }
    public void setPage(Integer page) { this.page = page; }

    public Integer getLimit() { return limit; }
    public void setLimit(Integer limit) { this.limit = limit; }
}
