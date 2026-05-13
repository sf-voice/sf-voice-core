//! sf-voice-api — http service that fronts the core stack.
//!
//! prod domain: https://api.sf-voice.sh
//! dev: http://127.0.0.1:8080 (via `mise run core:dev` or `cargo run -p sf-voice-api`)
//!
//! data stores wired here:
//!   - duckdb : embedded analytical, opens DUCKDB_PATH on startup
//!              (defaults to ./data/sf_voice.duckdb).
//!   - mysql  : not wired yet — DATABASE_URL is in .env ready to consume.
//!              add `sqlx` + a pool to AppState when reservations / orgs
//!              start landing.

use std::{
    net::SocketAddr,
    path::Path,
    sync::{Arc, Mutex},
};

use axum::{
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::get,
    Json, Router,
};
use duckdb::Connection;
use serde::Serialize;
use serde_json::json;
use tower_http::{cors::CorsLayer, trace::TraceLayer};

// shared state injected into every handler via axum's State extractor.
// duckdb's `Connection` is Send but not Sync, so we wrap in a Mutex.
// for read-heavy workloads we can later switch to per-request
// `try_clone()` or pool with r2d2 — both fine evolutions from here.
#[derive(Clone)]
struct AppState {
    db: Arc<Mutex<Connection>>,
    db_path: String,
}

#[derive(Serialize)]
struct Hello {
    message: String,
    service: &'static str,
    version: &'static str,
}

// GET /api/hello — sanity endpoint, no db. keep around as the first
// thing a new dev curls to confirm the loop (browser → api → response).
async fn hello() -> Json<Hello> {
    Json(Hello {
        message: "hello from sf-voice-api".to_string(),
        service: "sf-voice-api",
        version: env!("CARGO_PKG_VERSION"),
    })
}

// GET /healthz — flat 200 for liveness probes (caddy / k8s / uptime).
// intentionally does NOT touch the db — readiness lives elsewhere.
async fn healthz() -> &'static str {
    "ok"
}

async fn default() -> &'static str {
    "<div>Hello you might want to see https://app.sf-voice.sh</div>"
}

// GET /api/db/ping — proves duckdb is wired and queryable. returns the
// engine version and the path we opened, so a passing curl confirms
// both file location and connection are healthy in one call.
async fn db_ping(State(state): State<AppState>) -> Result<Json<serde_json::Value>, ApiError> {
    let conn = state.db.lock().map_err(|_| ApiError::Poisoned)?;
    let version: String = conn
        .query_row("SELECT version()", [], |row| row.get(0))
        .map_err(ApiError::Duckdb)?;
    let answer: i64 = conn
        .query_row("SELECT 42", [], |row| row.get(0))
        .map_err(ApiError::Duckdb)?;

    Ok(Json(json!({
        "duckdb_version": version,
        "path": state.db_path,
        "select_42": answer,
    })))
}

// minimal error type. expand with per-variant status codes once we have
// more than one kind of failure mode worth distinguishing to clients.
enum ApiError {
    Duckdb(duckdb::Error),
    Poisoned,
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let msg = match self {
            ApiError::Duckdb(e) => format!("duckdb error: {e}"),
            ApiError::Poisoned => "internal lock poisoned".to_string(),
        };
        tracing::error!("api error: {msg}");
        (StatusCode::INTERNAL_SERVER_ERROR, msg).into_response()
    }
}

fn open_duckdb() -> (Connection, String) {
    // .env loads into env via mise; fall back to a sensible default so
    // running `cargo run -p sf-voice-api` standalone (no mise) still works.
    let path = std::env::var("DUCKDB_PATH").unwrap_or_else(|_| "./data/sf_voice.duckdb".into());

    // make sure the parent dir exists — duckdb won't mkdir for us, and
    // a fresh checkout has no ./data/.
    if let Some(parent) = Path::new(&path).parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)
                .unwrap_or_else(|e| panic!("create duckdb parent dir {parent:?}: {e}"));
        }
    }

    let conn =
        Connection::open(&path).unwrap_or_else(|e| panic!("opening duckdb at {path} failed: {e}"));

    (conn, path)
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "sf_voice_api=info,tower_http=info".into()),
        )
        .init();

    let (conn, db_path) = open_duckdb();
    tracing::info!("duckdb opened at {db_path}");

    let state = AppState {
        db: Arc::new(Mutex::new(conn)),
        db_path,
    };

    let app = Router::new()
        .route("/api/hello", get(hello))
        .route("/api/db/ping", get(db_ping))
        .route("/healthz", get(healthz))
        .route("/", get(default))
        .with_state(state)
        // permissive cors is fine for the scaffold — frontend on :5173 in
        // dev, app.sf-voice.sh in prod. tighten to an explicit allowlist
        // once auth and cookies enter the picture.
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http());

    let addr: SocketAddr = "0.0.0.0:8080".parse().expect("hardcoded addr parses");
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .unwrap_or_else(|e| panic!("bind {addr} failed: {e}"));

    tracing::info!("sf-voice-api listening on http://{addr}");
    axum::serve(listener, app)
        .await
        .expect("axum::serve returned an error");
}
