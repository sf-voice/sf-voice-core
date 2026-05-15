use sea_orm::{ConnectOptions, Database, DatabaseConnection};

use crate::error::AppError;

pub async fn connect() -> Result<DatabaseConnection, AppError> {
    let url = std::env::var("DATABASE_URL")
        .map_err(|_| AppError::Internal("DATABASE_URL not set — see .env.example".into()))?;

    let mut opts = ConnectOptions::new(url);
    opts.max_connections(10);

    let db = Database::connect(opts).await?;
    tracing::info!("mysql pool connected");
    Ok(db)
}
