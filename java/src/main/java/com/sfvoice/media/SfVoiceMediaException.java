package com.sfvoice.media;

/** thrown by every client method on a non-2xx API response. */
public class SfVoiceMediaException extends Exception {

    private final String code;
    private final int status;

    public SfVoiceMediaException(String code, String message, int status) {
        super(message);
        this.code = code;
        this.status = status;
    }

    /** machine-readable error code from the API (e.g. "not_found"). */
    public String getCode() { return code; }

    /** HTTP status code. */
    public int getStatus() { return status; }
}
