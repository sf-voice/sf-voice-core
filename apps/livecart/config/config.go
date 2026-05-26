// env-driven config — fails fast on missing required vars.
package config

import (
	"fmt"
	"os"
	"strings"

	"github.com/joho/godotenv"
)

type Config struct {
	APIKey         string
	BaseURL        string
	SampleMediaURL string
}

func Load() (*Config, error) {
	// load .env if present — optional, never required
	_ = godotenv.Load()

	apiKey := strings.TrimSpace(os.Getenv("SF_VOICE_API_KEY"))
	if apiKey == "" {
		return nil, fmt.Errorf("required env var missing: SF_VOICE_API_KEY")
	}

	baseURL := strings.TrimSpace(os.Getenv("SF_VOICE_BASE_URL"))
	if baseURL == "" {
		baseURL = "https://api.sf-voice.com"
	}

	return &Config{
		APIKey:         apiKey,
		BaseURL:        baseURL,
		SampleMediaURL: strings.TrimSpace(os.Getenv("SAMPLE_MEDIA_URL")),
	}, nil
}
