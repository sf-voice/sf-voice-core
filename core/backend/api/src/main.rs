mod ai_models;
mod auth;
mod aws;
mod aws_creds;
mod cloudformation;
mod db;
mod duckdb_schema;
mod encryption;
mod error;
mod events;
mod internal_bucket;
mod jobs;
mod middleware;
mod models;
mod openai;
mod routes;
mod slack;
mod state;
mod vad;

use std::{
    net::SocketAddr,
    path::Path,
    sync::{Arc, Mutex},
};

use axum::{extract::State, routing::get, Json, Router};
use duckdb::Connection;
use serde::Serialize;
use serde_json::json;
use tower_http::{cors::CorsLayer, trace::TraceLayer};

use crate::{error::AppError, events::EventBroker, state::AppState};

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
async fn healthz() -> &'static str {
    "ok"
}

async fn default() -> &'static str {
    "<div>Hello you might want to see https://app.sf-voice.sh</div>"
}

async fn db_ping(State(state): State<AppState>) -> Result<Json<serde_json::Value>, AppError> {
    let conn = state.db.lock().map_err(|_| AppError::Poisoned)?;
    let version: String = conn.query_row("SELECT version()", [], |row| row.get(0))?;
    let answer: i64 = conn.query_row("SELECT 42", [], |row| row.get(0))?;

    Ok(Json(json!({
        "duckdb_version": version,
        "path": state.db_path,
        "select_42": answer,
    })))
}

// GET /api/db/mysql/ping — proves the mysql connection + schema-sync
// completed. mirrors /api/db/ping in shape so the two stores look the
// same to ops.
async fn mysql_ping(State(state): State<AppState>) -> Result<Json<serde_json::Value>, AppError> {
    use sea_orm::{ConnectionTrait, Statement};
    let backend = state.orm.get_database_backend();
    let row = state
        .orm
        .query_one_raw(Statement::from_string(
            backend,
            "SELECT VERSION() AS v, 42 AS forty_two".to_string(),
        ))
        .await?
        .ok_or_else(|| AppError::Internal("mysql ping returned no row".into()))?;
    let version: String = row
        .try_get::<String>("", "v")
        .map_err(|e| AppError::Internal(e.to_string()))?;
    let answer: i64 = row
        .try_get::<i64>("", "forty_two")
        .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(Json(json!({
        "mysql_version": version,
        "select_42": answer,
    })))
}

fn open_duckdb() -> (Connection, String) {
    let path = std::env::var("DUCKDB_PATH").unwrap_or_else(|_| "./data/sf_voice.duckdb".into());

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
                .unwrap_or_else(|_| "sf_voice_api=info,tower_http=info,sea_orm=warn".into()),
        )
        .init();

    let (conn, db_path) = open_duckdb();
    tracing::info!("duckdb opened at {db_path}");
    let duckdb_arc = std::sync::Arc::new(Mutex::new(conn));
    duckdb_schema::bootstrap(&duckdb_arc)
        .unwrap_or_else(|e| panic!("duckdb bootstrap failed: {e}"));

    let orm = db::connect()
        .await
        .unwrap_or_else(|e| panic!("mysql connect failed: {e}"));

    entities::pre_sync_extras(&orm)
        .await
        .unwrap_or_else(|e| panic!("pre_sync_extras failed: {e}"));
    orm.get_schema_registry("entities::*")
        .sync(&orm)
        .await
        .unwrap_or_else(|e| panic!("schema-sync failed: {e}"));
    entities::apply_extras(&orm)
        .await
        .unwrap_or_else(|e| panic!("apply_extras failed: {e}"));
    tracing::info!("mysql schema synced");

    let http = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(15))
        .build()
        .expect("reqwest client builds");
    let broker = Arc::new(EventBroker::new());

    let state = AppState {
        orm,
        db: duckdb_arc,
        db_path,
        http,
        broker,
    };

    // job runner — single in-process worker. polls jobs.status='queued'.
    tokio::spawn(jobs::run(state.clone()));

    let app = Router::new()
        .route("/api/hello", get(hello))
        .route("/api/db/ping", get(db_ping))
        .route("/api/db/mysql/ping", get(mysql_ping))
        .route("/healthz", get(healthz))
        .route("/", get(default))
        .nest("/api", routes::router())
        // internal-only routes: bearer-token gated by their own layer,
        // mounted SEPARATELY from the customer router so they can never
        // inherit cookie auth or vice versa.
        .nest("/api/_internal", routes::internal::router())
        .layer(axum::middleware::from_fn_with_state(
            state.clone(),
            middleware::maybe_auth,
        ))
        .with_state(state)
        .layer(
            CorsLayer::new()
                .allow_origin([
                    "http://localhost:3000".parse().unwrap(),
                    "http://127.0.0.1:3000".parse().unwrap(),
                    "https://app.sf-voice.sh".parse().unwrap(),
                ])
                .allow_credentials(true)
                .allow_headers([
                    axum::http::header::CONTENT_TYPE,
                    axum::http::header::ACCEPT,
                    axum::http::header::AUTHORIZATION,
                ])
                .allow_methods([
                    axum::http::Method::GET,
                    axum::http::Method::POST,
                    axum::http::Method::PATCH,
                    axum::http::Method::DELETE,
                    axum::http::Method::OPTIONS,
                ]),
        )
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
