package signoz

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestUtilizationClampAndRatio(t *testing.T) {
	// 1s of CPU over a 2s window on a 2-core box → 0.25.
	got := ratio(1*time.Second, 2*time.Second, 2)
	if got != 0.25 {
		t.Fatalf("ratio = %v, want 0.25", got)
	}
	if r := ratio(10*time.Second, 1*time.Second, 1); r != 1 {
		t.Fatalf("ratio should clamp to 1, got %v", r)
	}
	if r := ratio(-1*time.Second, 1*time.Second, 1); r != 0 {
		t.Fatalf("ratio should clamp to 0, got %v", r)
	}
}

// ratio mirrors cpuSampler.utilization's arithmetic for direct testing.
func ratio(dCPU, dWall time.Duration, numCPU float64) float64 {
	if dWall <= 0 || numCPU <= 0 {
		return 0
	}
	u := dCPU.Seconds() / (dWall.Seconds() * numCPU)
	if u < 0 {
		return 0
	}
	if u > 1 {
		return 1
	}
	return u
}

func TestPyroscopeNameEncoding(t *testing.T) {
	a := &Agent{cfg: Config{ServiceName: "svc", Labels: map[string]string{"env": "prod", "az": "a"}}}
	if got, want := a.pyroscopeName(), "svc.cpu{az=a,env=prod}"; got != want {
		t.Fatalf("pyroscopeName = %q, want %q (labels must be sorted)", got, want)
	}

	b := &Agent{cfg: Config{ServiceName: "svc"}}
	if got, want := b.pyroscopeName(), "svc.cpu"; got != want {
		t.Fatalf("pyroscopeName = %q, want %q", got, want)
	}
}

func TestOTLPMetricsJSONShape(t *testing.T) {
	util := 0.42
	count := "7"
	payload := otlpRequest{ResourceMetrics: []otlpResourceMetrics{{
		Resource: otlpResource{Attributes: []otlpKV{stringAttr("service.name", "svc")}},
		ScopeMetrics: []otlpScopeMetrics{{
			Scope: otlpScope{Name: "n", Version: "0.1.0"},
			Metrics: []otlpMetric{
				{Name: "process.cpu.utilization", Unit: "1", Gauge: &otlpGauge{
					DataPoints: []otlpNumberDataPoint{{TimeUnixNano: "1", AsDouble: &util}}}},
				{Name: "process.runtime.go.goroutines", Gauge: &otlpGauge{
					DataPoints: []otlpNumberDataPoint{{TimeUnixNano: "1", AsInt: &count}}}},
			},
		}},
	}}}

	b, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	out := string(b)
	for _, want := range []string{
		`"resourceMetrics"`, `"scopeMetrics"`, `"process.cpu.utilization"`,
		`"asDouble":0.42`, `"asInt":"7"`, `"timeUnixNano":"1"`,
		`"stringValue":"svc"`,
	} {
		if !strings.Contains(out, want) {
			t.Errorf("OTLP JSON missing %s\nfull: %s", want, out)
		}
	}
	// int64 fields must be JSON strings, not numbers.
	if strings.Contains(out, `"timeUnixNano":1`) {
		t.Error("timeUnixNano must be encoded as a string per proto3 JSON mapping")
	}
}
