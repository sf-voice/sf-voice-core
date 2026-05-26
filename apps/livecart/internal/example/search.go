// search runs a query and prints formatted results.
package example

import (
	"context"
	"fmt"
	"strings"

	sfvoice "github.com/sf-voice/sf-voice-media-go"
)

// Search queries the API and pretty-prints results to stdout.
func Search(ctx context.Context, client *sfvoice.Client, query string, assetIDs []string, types []string) error {
	req := sfvoice.SearchRequest{
		Query: query,
	}
	if len(assetIDs) > 0 {
		req.AssetIDs = assetIDs
	}
	if len(types) > 0 {
		req.Types = types
	}

	resp, err := client.Search(ctx, req)
	if err != nil {
		return fmt.Errorf("search: %w", err)
	}

	fmt.Printf("\U0001f50d results for %q (%d total):\n", query, resp.PageInfo.Total)
	if len(resp.Results) == 0 {
		fmt.Println("  (no results)")
		return nil
	}

	for i, r := range resp.Results {
		start := msToTime(uint64(r.StartMs))
		end := msToTime(uint64(r.EndMs))
		matchType := strings.ReplaceAll(r.MatchType, "_", " ")
		fmt.Printf("  %d. score=%.2f  %s–%s  %s\n", i+1, r.Score, start, end, matchType)
	}
	return nil
}

func msToTime(ms uint64) string {
	s := ms / 1000
	return fmt.Sprintf("%d:%02d", s/60, s%60)
}
