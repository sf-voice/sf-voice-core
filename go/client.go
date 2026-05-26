// Package sfvoice provides a client for the sf-voice media API.
//
// Quick start:
//
//	client := sfvoice.New("https://api.sf-voice.com", os.Getenv("SF_VOICE_API_KEY"))
//
//	resp, err := client.Ingest(ctx, sfvoice.IngestRequest{
//	    Source: "url",
//	    URL:    "https://example.com/call.mp4",
//	})
//	if err != nil {
//	    log.Fatal(err)
//	}
//	fmt.Println(resp.TaskID)
package sfvoice

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"time"
)

// Client is the sf-voice media API client.
// It is safe for concurrent use; create one and reuse it.
type Client struct {
	baseURL    string
	apiKey     string
	httpClient *http.Client
}

// New creates a client.
//
// baseURL should not have a trailing slash (e.g. "https://api.sf-voice.com").
// apiKey is sent as X-API-Key on every request.
func New(baseURL, apiKey string) *Client {
	return &Client{
		baseURL: baseURL,
		apiKey:  apiKey,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// NewWithHTTPClient creates a client using a custom *http.Client.
// Useful for setting custom timeouts, transports, or test doubles.
func NewWithHTTPClient(baseURL, apiKey string, httpClient *http.Client) *Client {
	return &Client{baseURL: baseURL, apiKey: apiKey, httpClient: httpClient}
}

// ── internal helpers ──────────────────────────────────────────────────────

func (c *Client) do(ctx context.Context, method, path string, body any, out any) error {
	var bodyReader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("sfvoice: marshal request: %w", err)
		}
		bodyReader = bytes.NewReader(b)
	}

	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, bodyReader)
	if err != nil {
		return fmt.Errorf("sfvoice: build request: %w", err)
	}

	req.Header.Set("X-API-Key", c.apiKey)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("sfvoice: http: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNoContent {
		return nil
	}

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("sfvoice: read response: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		var env apiErrorEnvelope
		code, message := "http_error", fmt.Sprintf("request failed with status %d", resp.StatusCode)
		if json.Unmarshal(respBody, &env) == nil && env.Error.Code != "" {
			code = env.Error.Code
			message = env.Error.Message
		}
		return &Error{Code: code, Message: message, Status: resp.StatusCode}
	}

	if out != nil {
		if err := json.Unmarshal(respBody, out); err != nil {
			return fmt.Errorf("sfvoice: decode response: %w", err)
		}
	}
	return nil
}

// ── public API ────────────────────────────────────────────────────────────

// Ingest submits a media file for ingestion from a URL or S3 key.
// It returns immediately with a TaskID you can poll with GetTask or PollTask.
func (c *Client) Ingest(ctx context.Context, req IngestRequest) (IngestResponse, error) {
	var out IngestResponse
	return out, c.do(ctx, http.MethodPost, "/v1/ingest", req, &out)
}

// GetTask fetches the current state of an ingestion task.
func (c *Client) GetTask(ctx context.Context, taskID string) (Task, error) {
	var out Task
	return out, c.do(ctx, http.MethodGet, "/v1/tasks/"+url.PathEscape(taskID), nil, &out)
}

// ListAssets returns a paginated list of assets. Pass 0 for page or limit to use server defaults.
func (c *Client) ListAssets(ctx context.Context, page, limit int) (AssetListResponse, error) {
	path := "/v1/assets"
	if page > 0 || limit > 0 {
		q := url.Values{}
		if page > 0 {
			q.Set("page", strconv.Itoa(page))
		}
		if limit > 0 {
			q.Set("limit", strconv.Itoa(limit))
		}
		path += "?" + q.Encode()
	}
	var out AssetListResponse
	return out, c.do(ctx, http.MethodGet, path, nil, &out)
}

// GetAsset fetches a single asset by ID.
func (c *Client) GetAsset(ctx context.Context, assetID string) (Asset, error) {
	var out Asset
	return out, c.do(ctx, http.MethodGet, "/v1/assets/"+url.PathEscape(assetID), nil, &out)
}

// DeleteAsset soft-deletes an asset. The backend retains the record but
// excludes it from list results. Returns nil on HTTP 204.
func (c *Client) DeleteAsset(ctx context.Context, assetID string) error {
	return c.do(ctx, http.MethodDelete, "/v1/assets/"+url.PathEscape(assetID), nil, nil)
}

// Search runs a semantic search across indexed media.
func (c *Client) Search(ctx context.Context, req SearchRequest) (SearchResponse, error) {
	var out SearchResponse
	return out, c.do(ctx, http.MethodPost, "/v1/search", req, &out)
}

// PollTask polls GetTask at intervalMs intervals until the task reaches a terminal
// state (ready or failed), then returns the final Task.
//
// Returns *PollTimeoutError if timeoutMs elapses before a terminal state is reached.
func (c *Client) PollTask(ctx context.Context, taskID string, intervalMs, timeoutMs int64) (Task, error) {
	deadline := time.Now().Add(time.Duration(timeoutMs) * time.Millisecond)
	interval := time.Duration(intervalMs) * time.Millisecond

	for {
		task, err := c.GetTask(ctx, taskID)
		if err != nil {
			return Task{}, err
		}
		if task.Status.IsTerminal() {
			return task, nil
		}

		remaining := time.Until(deadline)
		if remaining <= 0 {
			return Task{}, &PollTimeoutError{TaskID: taskID, TimeoutMs: timeoutMs}
		}

		sleep := interval
		if sleep > remaining {
			sleep = remaining
		}

		select {
		case <-ctx.Done():
			return Task{}, ctx.Err()
		case <-time.After(sleep):
		}
	}
}
