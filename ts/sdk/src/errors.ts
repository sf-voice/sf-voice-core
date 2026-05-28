import type { ApiErrorCode } from "./types.js";

/**
 * thrown by every SfVoiceMedia method on a non-2xx response.
 * `code` is the machine-readable error code from the API.
 * `status` is the HTTP status code.
 */
export class SfVoiceMediaError extends Error {
  readonly code: ApiErrorCode;
  readonly status: number;

  constructor(code: ApiErrorCode, message: string, status: number) {
    super(message);
    this.name = "SfVoiceMediaError";
    this.code = code;
    this.status = status;
    // restore prototype chain when targeting ES5
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

/**
 * thrown by `request` when a fetch stalls past the client-level timeout.
 */
export class SfVoiceMediaRequestTimeoutError extends Error {
  constructor(timeoutMs: number) {
    super(`request timed out after ${timeoutMs}ms`);
    this.name = "SfVoiceMediaRequestTimeoutError";
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

/**
 * thrown by `pollJob` when the timeout expires before the job
 * reaches a terminal state.
 */
export class SfVoiceMediaPollTimeoutError extends Error {
  readonly jobId: string;

  constructor(jobId: string, timeoutMs: number) {
    super(`job ${jobId} did not complete within ${timeoutMs}ms`);
    this.name = "SfVoiceMediaPollTimeoutError";
    this.jobId = jobId;
    Object.setPrototypeOf(this, new.target.prototype);
  }
}
