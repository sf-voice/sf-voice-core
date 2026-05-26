package sfvoice

// ── enums ─────────────────────────────────────────────────────────────────

type TaskStatus string

const (
	TaskStatusPending  TaskStatus = "pending"
	TaskStatusIndexing TaskStatus = "indexing"
	TaskStatusReady    TaskStatus = "ready"
	TaskStatusFailed   TaskStatus = "failed"
)

func (s TaskStatus) IsTerminal() bool {
	return s == TaskStatusReady || s == TaskStatusFailed
}

// ── pagination ────────────────────────────────────────────────────────────

type PageInfo struct {
	Total         int64  `json:"total"`
	Page          int    `json:"page"`
	Limit         int    `json:"limit"`
	NextPageToken string `json:"next_page_token,omitempty"`
}

// ── asset ─────────────────────────────────────────────────────────────────

type Asset struct {
	ID         string            `json:"id"`
	MediaType  string            `json:"media_type"`
	SourceType string            `json:"source_type"`
	Status     TaskStatus        `json:"status"`
	Metadata   map[string]string `json:"metadata,omitempty"`
	DurationMs *int64            `json:"duration_ms,omitempty"`
	CreatedAt  string            `json:"created_at"`
	UpdatedAt  string            `json:"updated_at"`
}

type AssetListResponse struct {
	Items    []Asset  `json:"items"`
	PageInfo PageInfo `json:"page_info"`
}

// ── ingest ────────────────────────────────────────────────────────────────

type IngestRequest struct {
	Source    string            `json:"source"`              // "url" | "s3"
	URL       string            `json:"url,omitempty"`
	S3Key     string            `json:"s3_key,omitempty"`
	MediaType string            `json:"media_type,omitempty"` // "video" | "audio"
	Metadata  map[string]string `json:"metadata,omitempty"`
}

type IngestResponse struct {
	AssetID string     `json:"asset_id"`
	TaskID  string     `json:"task_id"`
	Status  TaskStatus `json:"status"`
}

// ── tasks ─────────────────────────────────────────────────────────────────

type Task struct {
	TaskID      string     `json:"task_id"`
	AssetID     string     `json:"asset_id"`
	Status      TaskStatus `json:"status"`
	Error       string     `json:"error,omitempty"`
	CreatedAt   string     `json:"created_at"`
	CompletedAt string     `json:"completed_at,omitempty"`
}

// ── search ────────────────────────────────────────────────────────────────

type SearchRequest struct {
	Query     string   `json:"query"`
	Types     []string `json:"types,omitempty"`      // "visual" | "conversation" | "text_in_video"
	AssetIDs  []string `json:"asset_ids,omitempty"`
	Threshold float64  `json:"threshold,omitempty"`
	Page      int      `json:"page,omitempty"`
	Limit     int      `json:"limit,omitempty"`
}

type SearchResult struct {
	AssetID      string  `json:"asset_id"`
	Score        float64 `json:"score"`
	StartMs      int64   `json:"start_ms"`
	EndMs        int64   `json:"end_ms"`
	MatchType    string  `json:"match_type"`
	ThumbnailURL string  `json:"thumbnail_url,omitempty"`
}

type SearchResponse struct {
	Results  []SearchResult `json:"results"`
	PageInfo PageInfo       `json:"page_info"`
}

// ── internal ──────────────────────────────────────────────────────────────

type apiErrorEnvelope struct {
	Error apiErrorBody `json:"error"`
}

type apiErrorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}
