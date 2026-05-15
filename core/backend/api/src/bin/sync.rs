use sea_orm::Database;

#[tokio::main]
async fn main() {
    let url =
        std::env::var("DATABASE_URL").expect("DATABASE_URL not set — see .env (root of repo)");

    let db = Database::connect(&url)
        .await
        .unwrap_or_else(|e| panic!("mysql connect failed: {e}"));

    db.get_schema_registry("entities::*")
        .sync(&db)
        .await
        .unwrap_or_else(|e| panic!("schema-sync failed: {e}"));

    entities::apply_extras(&db)
        .await
        .unwrap_or_else(|e| panic!("apply_extras failed: {e}"));

    eprintln!("schema synced");
}
