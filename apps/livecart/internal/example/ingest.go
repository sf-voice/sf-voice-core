// ingest runs concurrent URL ingestion and blocks until all tasks are ready.
package example

import (
	"context"
	"fmt"
	"sync"
	"time"

	sfvoice "github.com/sf-voice/sf-voice-media-go"
)

// IngestResult holds the outcome of one ingested URL.
type IngestResult struct {
	URL     string
	AssetID string
	TaskID  string
	Elapsed time.Duration
	Err     error
}

// IngestAll ingests all URLs concurrently (up to concurrency at a time),
// polls each task until ready, and returns one result per URL.
func IngestAll(ctx context.Context, client *sfvoice.Client, urls []string, concurrency int) []IngestResult {
	if concurrency < 1 {
		concurrency = 1
	}

	sem := make(chan struct{}, concurrency)
	results := make([]IngestResult, len(urls))
	var wg sync.WaitGroup

	for i, url := range urls {
		wg.Add(1)
		go func(idx int, u string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			results[idx] = ingestOne(ctx, client, u)
		}(i, url)
	}

	wg.Wait()
	return results
}

func ingestOne(ctx context.Context, client *sfvoice.Client, url string) IngestResult {
	t0 := time.Now()

	resp, err := client.Ingest(ctx, sfvoice.IngestRequest{
		Source: "url",
		URL:    url,
	})
	if err != nil {
		return IngestResult{URL: url, Err: fmt.Errorf("ingest: %w", err)}
	}

	pollCtx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()

	task, err := client.PollTask(pollCtx, resp.TaskID, 1500, 300_000)
	if err != nil {
		return IngestResult{URL: url, AssetID: resp.AssetID, TaskID: resp.TaskID, Err: fmt.Errorf("poll: %w", err)}
	}
	if task.Status == sfvoice.TaskStatusFailed {
		return IngestResult{URL: url, AssetID: resp.AssetID, TaskID: resp.TaskID, Err: fmt.Errorf("indexing failed: %s", task.Error)}
	}

	return IngestResult{
		URL:     url,
		AssetID: resp.AssetID,
		TaskID:  resp.TaskID,
		Elapsed: time.Since(t0),
	}
}
