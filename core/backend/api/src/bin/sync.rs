//! standalone schema bootstrap. used by `mise run db:migrate` to land
//! schema changes without booting the full api. mirrors the DDL block
//! in main.rs.

use sea_orm::Database;

#[tokio::main]
async fn main() {
    let url =
        std::env::var("DATABASE_URL").expect("DATABASE_URL not set — see .env (root of repo)");

    let db = Database::connect(&url)
        .await
        .unwrap_or_else(|e| panic!("mysql connect failed: {e}"));

    entities::bootstrap_schema(&db)
        .await
        .unwrap_or_else(|e| panic!("schema bootstrap failed: {e}"));

    eprintln!("schema bootstrapped");
}
