//go:build !unix

package signoz

import (
	"errors"
	"time"
)

// errCPUUnsupported is returned by processCPUTime on platforms without
// getrusage (e.g. Windows). The metrics loop logs it once and the profiler
// loop is unaffected.
var errCPUUnsupported = errors.New("process CPU sampling is not supported on this platform")

func processCPUTime() (time.Duration, error) {
	return 0, errCPUUnsupported
}
