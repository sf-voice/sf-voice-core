//! shared state injected into every handler via axum's `State` extractor.

use std::sync::{Arc, Mutex};

use duckdb::Connection;
use reqwest::Client;
use sea_orm::DatabaseConnection;

use crate::ai_models::ModelPaths;
use crate::diarize::Diarizer;
use crate::events::EventBroker;
use crate::whisper::Whisper;

#[derive(Clone)]
pub struct AppState {
    pub orm: DatabaseConnection,
    pub db: Arc<Mutex<Connection>>,
    pub db_path: String,
    pub http: Client,
    pub broker: Arc<EventBroker>,

    // local ml stack — loaded once at boot from MODELS_S3_BUCKET via
    // `ai_models::bootstrap()`. Arc-wrapped so cloning AppState (every
    // handler call) is cheap.
    pub model_paths: Arc<ModelPaths>,
    pub whisper: Arc<Whisper>,
    pub diarizer: Arc<Diarizer>,
}
