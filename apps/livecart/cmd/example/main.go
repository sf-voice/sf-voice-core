// sf-voice media SDK demo — concurrent ingest + search.
//
// usage:
//
//	go run ./cmd/demo -urls "https://a.mp4,https://b.mp3" -query "product launch"
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"strings"

	sfvoice "github.com/sf-voice/sf-voice-media-go"
	"github.com/sf-voice/sf-voice-media-go/example/config"
	"github.com/sf-voice/sf-voice-media-go/example/internal/example"
)

// main parses command-line flags, loads configuration, ingests one or more media URLs concurrently,
// collects successful asset IDs, and runs a search query against those assets.
// 
// Flags:
//   -urls       comma-separated media URLs to ingest (falls back to SAMPLE_MEDIA_URL from config)
//   -query      required search query to run after ingest
//   -types      optional comma-separated match types: visual, conversation, text_in_video
//   -concurrency max concurrent ingests (default 4)
// 
// Exit codes:
//   1 on configuration load failure or when no assets were ingested successfully,
//   2 when required inputs (urls or query) are missing.
func main() {
	urlsFlag := flag.String("urls", "", "comma-separated media URLs to ingest")
	queryFlag := flag.String("query", "", "search query to run after ingest")
	typesFlag := flag.String("types", "", "comma-separated match types: visual,conversation,text_in_video")
	concFlag := flag.Int("concurrency", 4, "max concurrent ingests")
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}

	rawURLs := strings.TrimSpace(*urlsFlag)
	if rawURLs == "" {
		rawURLs = cfg.SampleMediaURL
	}
	if rawURLs == "" {
		fmt.Fprintln(os.Stderr, "error: provide -urls or set SAMPLE_MEDIA_URL")
		os.Exit(2)
	}

	query := strings.TrimSpace(*queryFlag)
	if query == "" {
		fmt.Fprintln(os.Stderr, "error: -query is required")
		os.Exit(2)
	}

	urls := strings.Split(rawURLs, ",")
	for i, u := range urls {
		urls[i] = strings.TrimSpace(u)
	}

	var types []string
	if *typesFlag != "" {
		for _, t := range strings.Split(*typesFlag, ",") {
			types = append(types, strings.TrimSpace(t))
		}
	}

	client := sfvoice.New(cfg.BaseURL, cfg.APIKey)
	ctx := context.Background()

	fmt.Printf("ingesting %d URL(s) with concurrency=%d …\n", len(urls), *concFlag)

	results := example.IngestAll(ctx, client, urls, *concFlag)

	var assetIDs []string
	for _, r := range results {
		if r.Err != nil {
			fmt.Fprintf(os.Stderr, "  ✗ %s: %v\n", r.URL, r.Err)
		} else {
			fmt.Printf("  ✓ asset_id=%-30s  %.1fs  %s\n", r.AssetID, r.Elapsed.Seconds(), r.URL)
			assetIDs = append(assetIDs, r.AssetID)
		}
	}

	if len(assetIDs) == 0 {
		fmt.Fprintln(os.Stderr, "no assets ingested successfully")
		os.Exit(1)
	}

	fmt.Println()
	if err := example.Search(ctx, client, query, assetIDs, types); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}
