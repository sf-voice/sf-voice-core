// scaffolding module — public API isn't called from main.rs yet, so the
// per-symbol "never used" warnings are noise. once a real consumer in
// the binary uses VadClient::connect_and_join etc., remove this allow.
#![allow(dead_code)]

//! VAD client — talks to ellie's `/socket/vad` websocket.
//!
//! ellie hosts a Phoenix Channel at `ws://ellie-ai:4001/socket/vad/websocket`
//! that wraps silero VAD. one channel pid per audio stream; the server
//! keeps the recurrent state, hysteresis, and end-of-turn detection.
//!
//! ## wire format we send
//!
//! - sample rate: **16000 Hz** (declared at join; ellie also supports 8000)
//! - dtype:       **float32 little-endian**
//! - chunk size:  **512 samples = 2048 bytes per push** (at 16 kHz)
//!   (at 8 kHz it's 256 samples / 1024 bytes — not used by this client.)
//! - cadence:     one chunk every 32 ms; falling behind doesn't crash
//!   but inflates EOT latency.
//!
//! the server echoes the spec it expects on join — `VadClient::join`
//! captures it in `JoinAck` so callers don't have to hardcode anything.
//!
//! ## wire format we receive
//!
//! per chunk, one JSON frame:
//!
//! ```json
//! { "prob": 0.42 }                          // no transition
//! { "prob": 0.91, "event": "speech_start" } // hysteresis flipped
//! { "prob": 0.05, "event": "speech_end" }   // EOT fired
//! ```
//!
//! consumers that only care about end-of-turn should match on
//! `Event::SpeechEnd`. probability is reported on every frame so
//! callers can roll their own thresholds if needed.
//!
//! ## auth
//!
//! `INTERNAL_API_TOKEN` (shared with ellie + resto). passed as the
//! `token` query param on connect.
//!
//! ## phoenix v2 binary push format
//!
//! audio frames are not JSON. Phoenix's v2 serializer uses a tight
//! binary push frame:
//!
//! ```text
//! byte 0:    0           # kind = push from client
//! byte 1:    jl          # join_ref length
//! byte 2:    rl          # ref length
//! byte 3:    tl          # topic length
//! byte 4:    el          # event length
//! bytes 5+:  join_ref || ref || topic || event || payload (audio)
//! ```
//!
//! `join_ref` matches the join phx_ref; `ref` is a per-push id we
//! increment so the server can correlate (we don't await replies on
//! audio pushes today — `frame` events arrive as separate server-
//! initiated messages).

use std::sync::atomic::{AtomicU64, Ordering};

use anyhow::{anyhow, bail, Context, Result};
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use tokio_tungstenite::{
    connect_async,
    tungstenite::{
        handshake::client::generate_key, http::Request as HttpRequest, protocol::Message,
    },
    MaybeTlsStream, WebSocketStream,
};

type WsStream = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

/// what `recv_event` hands back per audio frame.
#[derive(Debug, Clone)]
pub struct Frame {
    pub prob: f32,
    pub event: Option<Event>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Event {
    SpeechStart,
    SpeechEnd,
}

/// what ellie tells us on join. mirror of the channel's `:ok, reply`.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct JoinAck {
    pub sample_rate: u32,
    pub samples_per_window: u32,
    pub bytes_per_window: u32,
    pub window_ms: u32,
    pub sample_dtype: String,
    pub speech_threshold: f32,
    pub silence_threshold: f32,
}

pub struct VadClient {
    ws: WsStream,
    join_ref: String,
    topic: String,
    next_ref: AtomicU64,
    pub ack: JoinAck,
}

impl VadClient {
    /// connect + join in one call. `topic_id` becomes the suffix of
    /// `vad:stream:<topic_id>` — anything unique per stream.
    ///
    /// `ws_url` should look like `ws://ellie-ai:4001/socket/vad`.
    /// the `/websocket?vsn=2.0.0&token=...` suffix is appended here.
    pub async fn connect_and_join(
        ws_url: &str,
        token: &str,
        topic_id: &str,
        sample_rate: u32,
        silence_ms: u32,
    ) -> Result<Self> {
        let url = format!(
            "{ws_url}/websocket?vsn=2.0.0&token={token}",
            token = urlencode(token)
        );

        // explicit Request so we can sanity-check the scheme. Phoenix's
        // socket endpoint upgrades any client that speaks ws — no extra
        // headers needed beyond the standard websocket handshake.
        let request = HttpRequest::builder()
            .uri(&url)
            .header("Host", host_from_url(&url)?)
            .header("Upgrade", "websocket")
            .header("Connection", "Upgrade")
            .header("Sec-WebSocket-Key", generate_key())
            .header("Sec-WebSocket-Version", "13")
            .body(())?;

        let (ws, _resp) = connect_async(request)
            .await
            .with_context(|| format!("connect_async to {url}"))?;

        let join_ref = "1".to_string();
        let topic = format!("vad:stream:{topic_id}");

        let mut client = Self {
            ws,
            join_ref: join_ref.clone(),
            topic: topic.clone(),
            next_ref: AtomicU64::new(2),
            // placeholder; overwritten by join reply.
            ack: JoinAck {
                sample_rate: 0,
                samples_per_window: 0,
                bytes_per_window: 0,
                window_ms: 0,
                sample_dtype: String::new(),
                speech_threshold: 0.0,
                silence_threshold: 0.0,
            },
        };

        client.join(sample_rate, silence_ms).await?;
        Ok(client)
    }

    /// send `phx_join` and await `phx_reply` with the channel's format spec.
    async fn join(&mut self, sample_rate: u32, silence_ms: u32) -> Result<()> {
        let join_payload = serde_json::json!({
            "sample_rate": sample_rate,
            "silence_ms": silence_ms,
        });

        let join_msg = serde_json::json!([
            self.join_ref,
            self.join_ref,  // ref == join_ref for the join itself
            self.topic,
            "phx_join",
            join_payload,
        ]);

        self.ws
            .send(Message::Text(join_msg.to_string()))
            .await
            .context("send phx_join")?;

        // drain until we see the phx_reply for our join_ref. phoenix
        // can interleave `phx_close`, server pings, etc. — those are
        // pre-handshake noise we ignore until the reply arrives.
        loop {
            let frame = self
                .ws
                .next()
                .await
                .ok_or_else(|| anyhow!("ws closed before phx_reply"))??;

            let text = match frame {
                Message::Text(t) => t,
                Message::Ping(p) => {
                    self.ws.send(Message::Pong(p)).await.ok();
                    continue;
                }
                Message::Close(_) => bail!("ws closed mid-join"),
                _ => continue,
            };

            let parsed: serde_json::Value = serde_json::from_str(&text)?;
            // phoenix v2 frame: [join_ref, ref, topic, event, payload]
            let arr = parsed
                .as_array()
                .ok_or_else(|| anyhow!("expected phoenix v2 array frame, got {parsed}"))?;

            if arr.len() != 5 {
                continue;
            }

            let event = arr[3].as_str().unwrap_or("");
            if event == "phx_reply" {
                let status = arr[4]["status"].as_str().unwrap_or("");
                if status != "ok" {
                    bail!("phx_join rejected: {}", arr[4]);
                }
                let response = arr[4]["response"].clone();
                self.ack = serde_json::from_value(response)
                    .context("decode JoinAck — server schema drifted?")?;
                return Ok(());
            }
        }
    }

    /// push one window of audio. `samples` must be exactly
    /// `self.ack.samples_per_window` f32 values.
    pub async fn push_audio(&mut self, samples: &[f32]) -> Result<()> {
        if samples.len() != self.ack.samples_per_window as usize {
            bail!(
                "wrong window size: server wants {} samples/window @ {}Hz, got {}",
                self.ack.samples_per_window,
                self.ack.sample_rate,
                samples.len()
            );
        }

        // serialize as f32 little-endian — matches the channel's
        // <<sample::little-float-32 <- audio>> decode.
        let mut audio = Vec::with_capacity(samples.len() * 4);
        for s in samples {
            audio.extend_from_slice(&s.to_le_bytes());
        }

        let ref_id = self.next_ref.fetch_add(1, Ordering::Relaxed).to_string();
        let frame = encode_binary_push(&self.join_ref, &ref_id, &self.topic, "audio", &audio);

        self.ws
            .send(Message::Binary(frame))
            .await
            .context("send audio binary push")?;
        Ok(())
    }

    /// block until the next `frame` push from the server. returns
    /// `Ok(None)` if the channel closed cleanly.
    ///
    /// phx_reply messages (e.g. acks of audio pushes) are skipped here
    /// — callers that need them should reach into `recv_raw` instead.
    pub async fn recv_frame(&mut self) -> Result<Option<Frame>> {
        loop {
            let msg = match self.ws.next().await {
                Some(m) => m?,
                None => return Ok(None),
            };

            let text = match msg {
                Message::Text(t) => t,
                Message::Ping(p) => {
                    self.ws.send(Message::Pong(p)).await.ok();
                    continue;
                }
                Message::Close(_) => return Ok(None),
                _ => continue,
            };

            let parsed: serde_json::Value = serde_json::from_str(&text)?;
            let arr = match parsed.as_array() {
                Some(a) if a.len() == 5 => a,
                _ => continue,
            };

            if arr[3].as_str() == Some("frame") {
                let payload = &arr[4];
                let prob = payload["prob"].as_f64().unwrap_or(0.0) as f32;
                let event = match payload["event"].as_str() {
                    Some("speech_start") => Some(Event::SpeechStart),
                    Some("speech_end") => Some(Event::SpeechEnd),
                    _ => None,
                };
                return Ok(Some(Frame { prob, event }));
            }
            // any other event (phx_reply, phx_close, ...) — skip.
        }
    }
}

// ── phoenix v2 binary push encoder ────────────────────────────────────

fn encode_binary_push(
    join_ref: &str,
    push_ref: &str,
    topic: &str,
    event: &str,
    payload: &[u8],
) -> Vec<u8> {
    // header: kind, then four length bytes for the strings.
    let jl = join_ref.len();
    let rl = push_ref.len();
    let tl = topic.len();
    let el = event.len();

    // lengths are u8; assert at debug time so we never silently truncate.
    debug_assert!(jl <= u8::MAX as usize);
    debug_assert!(rl <= u8::MAX as usize);
    debug_assert!(tl <= u8::MAX as usize);
    debug_assert!(el <= u8::MAX as usize);

    let mut buf = Vec::with_capacity(5 + jl + rl + tl + el + payload.len());
    buf.push(0u8); // kind = push from client
    buf.push(jl as u8);
    buf.push(rl as u8);
    buf.push(tl as u8);
    buf.push(el as u8);
    buf.extend_from_slice(join_ref.as_bytes());
    buf.extend_from_slice(push_ref.as_bytes());
    buf.extend_from_slice(topic.as_bytes());
    buf.extend_from_slice(event.as_bytes());
    buf.extend_from_slice(payload);
    buf
}

// ── tiny helpers ──────────────────────────────────────────────────────

fn urlencode(s: &str) -> String {
    // good enough for a token value: the alphabet is base64-ish, but
    // we'll percent-encode anything that isn't unreserved per rfc3986.
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char)
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

fn host_from_url(url: &str) -> Result<String> {
    // ws://host:port/path  or  wss://host/path → "host:port"
    let after_scheme = url
        .split_once("://")
        .map(|(_, rest)| rest)
        .ok_or_else(|| anyhow!("url missing scheme: {url}"))?;
    let host = after_scheme.split('/').next().unwrap_or("");
    Ok(host.to_string())
}

// ── tests ─────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn binary_push_layout_matches_phoenix_v2_serializer() {
        // canonical example: join_ref="1", ref="2", topic="vad:stream:x",
        // event="audio", payload=<<0xAA, 0xBB>>
        let out = encode_binary_push("1", "2", "vad:stream:x", "audio", &[0xAA, 0xBB]);
        // header: 0, 1, 1, 12, 5
        assert_eq!(out[0], 0);
        assert_eq!(out[1], 1);
        assert_eq!(out[2], 1);
        assert_eq!(out[3], 12);
        assert_eq!(out[4], 5);
        assert_eq!(&out[5..6], b"1");
        assert_eq!(&out[6..7], b"2");
        assert_eq!(&out[7..19], b"vad:stream:x");
        assert_eq!(&out[19..24], b"audio");
        assert_eq!(&out[24..], &[0xAA, 0xBB]);
    }

    #[test]
    fn urlencode_passes_unreserved_and_percent_encodes_the_rest() {
        assert_eq!(urlencode("abc-123_.~"), "abc-123_.~");
        assert_eq!(urlencode("a/b c"), "a%2Fb%20c");
    }

    #[test]
    fn host_from_url_strips_scheme_and_path() {
        assert_eq!(
            host_from_url("ws://ellie-ai:4001/socket/vad").unwrap(),
            "ellie-ai:4001"
        );
        assert_eq!(
            host_from_url("wss://ellie-ai.sf-voice.sh/socket/vad/websocket").unwrap(),
            "ellie-ai.sf-voice.sh"
        );
    }
}
