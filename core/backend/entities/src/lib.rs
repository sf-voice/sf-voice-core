//! sf-voice typed schema. one module per table; this crate is the
//! source of truth for table shape, but DDL is hand-written below
//! rather than generated from the entity macros.
//!
//! WHY HAND-WRITTEN: SeaORM 2.0 RC's `schema-sync` produces malformed
//! SQL on a few common patterns (DROP INDEX with prefix indexes,
//! certain MODIFY COLUMN paths). Each occurrence wedges boot. We use
//! the entities for *queries* and run all DDL through `bootstrap_schema`,
//! a single idempotent function called at startup. The entity files
//! must stay in sync with the DDL by hand — there's no codegen.
//!
//! Convention: every state/role/kind column is `String` (VARCHAR(N))
//! with a SQL comment listing allowed values. No ENUM columns.

pub mod auth_identities;
pub mod calls;
pub mod chat_messages;
pub mod chat_threads;
pub mod documents;
pub mod embeddings;
pub mod invites;
pub mod jobs;
pub mod org_users;
pub mod orgs;
pub mod prompt_slices;
pub mod sessions;
pub mod transcripts;
pub mod users;

use sea_orm::{ConnectionTrait, DatabaseConnection, DbErr, Statement};

const DEFAULT_CHARSET: &str = "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";

/// idempotent schema bootstrap. CREATE TABLE IF NOT EXISTS for every
/// entity, plus FULLTEXT / CHECK / unique extras schema-sync can't
/// express. safe to run on every boot.
///
/// when adding/changing a column: edit the entity file (for queries)
/// AND the matching CREATE TABLE below. for an existing-column
/// modification, also add a one-shot `ALTER TABLE` block at the end
/// — see the migrations note inside.
pub async fn bootstrap_schema(db: &DatabaseConnection) -> Result<(), DbErr> {
    // --- tables, in FK-safe order (parents first) -----------------------

    create(
        db,
        "users",
        &[
            "id BINARY(16) NOT NULL PRIMARY KEY",
            "email VARCHAR(254) NOT NULL",
            "password_hash VARCHAR(255) NULL",
            "display_name VARCHAR(120) NULL",
            "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP",
            "updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP",
            "UNIQUE KEY uq_users_email (email)",
        ],
    )
    .await?;

    create(
        db,
        "orgs",
        &[
            "id BINARY(16) NOT NULL PRIMARY KEY",
            "name VARCHAR(255) NOT NULL",
            "slug VARCHAR(64) NOT NULL",
            "bucket_name VARCHAR(255) NULL",
            "bucket_prefix VARCHAR(512) NULL",
            "bucket_region VARCHAR(32) NULL",
            "bucket_role_arn VARCHAR(512) NULL",
            "bucket_external_id VARCHAR(128) NULL",
            "bucket_auth_method VARCHAR(16) NULL COMMENT \"'role' | 'keys'\"",
            "bucket_access_key_id VARCHAR(128) NULL",
            "bucket_secret_access_key_encrypted VARBINARY(512) NULL",
            "bucket_verified_at DATETIME NULL",
            "bucket_account_id VARCHAR(16) NULL",
            "config_repo_url VARCHAR(512) NULL",
            "slack_webhook_url VARCHAR(512) NULL",
            "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP",
            "updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP",
            "UNIQUE KEY uq_orgs_slug (slug)",
        ],
    )
    .await?;

    create(
        db,
        "org_users",
        &[
            "id BINARY(16) NOT NULL PRIMARY KEY",
            "org_id BINARY(16) NOT NULL",
            "user_id BINARY(16) NOT NULL",
            "role VARCHAR(16) NOT NULL DEFAULT 'member' COMMENT \"'owner' | 'member'\"",
            "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP",
            "KEY idx_org_users_user (user_id)",
        ],
    )
    .await?;

    create(
        db,
        "auth_identities",
        &[
            "id BINARY(16) NOT NULL PRIMARY KEY",
            "user_id BINARY(16) NOT NULL",
            "provider VARCHAR(32) NOT NULL",
            "subject VARCHAR(255) NOT NULL",
            "email VARCHAR(254) NULL",
            "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP",
        ],
    )
    .await?;

    create(
        db,
        "sessions",
        &[
            "id BINARY(32) NOT NULL PRIMARY KEY",
            "user_id BINARY(16) NOT NULL",
            "current_org_id BINARY(16) NOT NULL",
            "expires_at DATETIME NOT NULL",
            "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP",
            "last_used_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP",
            "ip VARCHAR(45) NULL",
            "user_agent VARCHAR(255) NULL",
            "KEY idx_sessions_user (user_id)",
            "KEY idx_sessions_expires (expires_at)",
        ],
    )
    .await?;

    create(
        db,
        "invites",
        &[
            "id BINARY(16) NOT NULL PRIMARY KEY",
            "org_id BINARY(16) NOT NULL",
            "email VARCHAR(254) NOT NULL",
            "role VARCHAR(16) NOT NULL DEFAULT 'member' COMMENT \"'owner' | 'member'\"",
            "token VARCHAR(64) NOT NULL",
            "invited_by BINARY(16) NOT NULL",
            "accepted_at DATETIME NULL",
            "expires_at DATETIME NOT NULL",
            "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP",
            "KEY idx_invites_org (org_id)",
            "KEY idx_invites_email (email)",
            "UNIQUE KEY uq_invites_token (token)",
        ],
    )
    .await?;

    create(
        db,
        "calls",
        &[
            "id BINARY(16) NOT NULL PRIMARY KEY",
            "org_id BINARY(16) NOT NULL",
            "external_id VARCHAR(255) NULL",
            "started_at DATETIME NOT NULL",
            "ended_at DATETIME NULL",
            "duration_ms INT NULL",
            "caller_number VARCHAR(32) NULL",
            "destination_number VARCHAR(32) NULL",
            "termination_reason VARCHAR(64) NULL",
            "audio_uri VARCHAR(1024) NULL",
            "caller_audio_uri VARCHAR(1024) NULL",
            "ai_audio_uri VARCHAR(1024) NULL",
            "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP",
            "updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP",
            "KEY idx_calls_org (org_id)",
        ],
    )
    .await?;

    create(db, "documents", &[
        "id BINARY(16) NOT NULL PRIMARY KEY",
        "type VARCHAR(32) NOT NULL COMMENT \"'internal' | 'customer' (reserved)\"",
        "media_kind VARCHAR(32) NOT NULL COMMENT \"'audio' | 'video' | 'image' | 'pdf' | 'spreadsheet' | 'markdown' | 'code' | 'web_url' | 'chat_export' | 'transcript_segment'\"",
        "source_kind VARCHAR(64) NOT NULL COMMENT \"'youtube' | 'upload' | 'call' | ...\"",
        "source_id BINARY(16) NULL",
        "source_url VARCHAR(1024) NULL",
        "bucket VARCHAR(255) NULL",
        "s3_key VARCHAR(1024) NULL",
        "filename VARCHAR(255) NULL",
        "mime_type VARCHAR(64) NULL",
        "duration_ms INT NULL",
        "processing_status VARCHAR(32) NOT NULL COMMENT \"'queued' | 'downloading' | 'extracting' | 'uploading' | 'ready' | 'failed'\"",
        "processing_error TEXT NULL",
        "job_id BINARY(16) NULL",
        "title VARCHAR(512) NULL",
        "folder VARCHAR(512) NULL",
        "tags JSON NULL",
        "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP",
        "updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP",
        "KEY idx_documents_status (processing_status)",
        "KEY idx_documents_folder (folder)",
        "KEY idx_documents_source (source_id)",
    ]).await?;

    create(db, "jobs", &[
        "id BINARY(16) NOT NULL PRIMARY KEY",
        "org_id BINARY(16) NOT NULL",
        "kind VARCHAR(32) NOT NULL COMMENT \"'ingest' | 'transcribe' | 'transcribe_document' | 'sandbox' | 'open_pr' | 'youtube_ingest'\"",
        "subject_type VARCHAR(32) NOT NULL",
        "subject_id BINARY(16) NULL",
        "status VARCHAR(32) NOT NULL COMMENT \"'queued' | 'running' | 'done' | 'failed' | 'cancelled'\"",
        "payload JSON NULL",
        "result JSON NULL",
        "error_message TEXT NULL",
        "progress_steps JSON NULL",
        "slack_thread_ts VARCHAR(32) NULL",
        "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP",
        "started_at DATETIME NULL",
        "finished_at DATETIME NULL",
        "KEY idx_jobs_status (status)",
    ]).await?;

    create(db, "prompt_slices", &[
        "id BINARY(16) NOT NULL PRIMARY KEY",
        "call_id BINARY(16) NOT NULL",
        "org_id BINARY(16) NOT NULL",
        "start_ms INT NOT NULL",
        "end_ms INT NOT NULL",
        "prompt_text TEXT NOT NULL",
        "status VARCHAR(32) NOT NULL COMMENT \"'draft' | 'sandboxed' | 'pr_open' | 'merged' | 'rejected'\"",
        "job_id BINARY(16) NULL",
        "pr_url VARCHAR(512) NULL",
        "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP",
        "updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP",
        "KEY idx_prompt_slices_call (call_id)",
    ]).await?;

    create(db, "transcripts", &[
        "id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY",
        "call_id BINARY(16) NULL",
        "document_id BINARY(16) NULL",
        "speaker_label VARCHAR(32) NOT NULL COMMENT \"calls: 'ai'|'caller'|'unknown'. documents: 'speaker_<n>'|'speaker_unknown'.\"",
        "start_ms INT NOT NULL",
        "end_ms INT NOT NULL",
        "text TEXT NOT NULL",
        "confidence FLOAT NULL",
        "model_version VARCHAR(64) NOT NULL",
        "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP",
        "KEY idx_transcripts_call (call_id)",
        "KEY idx_transcripts_document (document_id)",
        "CONSTRAINT chk_transcripts_subject CHECK ((call_id IS NOT NULL) <> (document_id IS NOT NULL))",
    ]).await?;

    create(
        db,
        "embeddings",
        &[
            "id BINARY(16) NOT NULL PRIMARY KEY",
            "document_id BINARY(16) NOT NULL",
            "chunk_index INT NOT NULL",
            "start_ms INT NULL",
            "end_ms INT NULL",
            "source_locator JSON NULL",
            "text TEXT NOT NULL",
            "model VARCHAR(64) NOT NULL",
            "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP",
            "KEY idx_embeddings_document (document_id)",
            "UNIQUE KEY uq_embeddings_chunk (document_id, chunk_index)",
        ],
    )
    .await?;

    create(
        db,
        "chat_threads",
        &[
            "id BINARY(16) NOT NULL PRIMARY KEY",
            "user_id BINARY(16) NOT NULL",
            "title VARCHAR(256) NOT NULL",
            "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP",
            "KEY idx_chat_threads_user (user_id)",
        ],
    )
    .await?;

    create(
        db,
        "chat_messages",
        &[
            "id BINARY(16) NOT NULL PRIMARY KEY",
            "thread_id BINARY(16) NOT NULL",
            "role VARCHAR(16) NOT NULL COMMENT \"'user' | 'assistant'\"",
            "content TEXT NOT NULL",
            "citations JSON NOT NULL",
            "pending_doc_ids JSON NOT NULL",
            "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP",
            "KEY idx_chat_messages_thread (thread_id)",
        ],
    )
    .await?;

    // --- post-table extras schema-sync would have flagged as drift -------

    // FULLTEXT on transcripts.text — included inline above? no: MySQL
    // requires FULLTEXT to be created separately for clarity, and
    // CREATE FULLTEXT INDEX errors if it already exists, so guard.
    create_index_if_missing(
        db,
        "transcripts",
        "ftx_transcripts_text",
        "CREATE FULLTEXT INDEX ftx_transcripts_text ON transcripts (text)",
    )
    .await?;

    // --- one-shot migrations for legacy databases ------------------------
    //
    // when changing an existing column on an already-deployed table,
    // add a guarded ALTER here. CREATE TABLE IF NOT EXISTS won't
    // re-shape an existing table, so column changes need explicit
    // ALTERs for environments that already created the table at the
    // older shape. all checks below are idempotent.

    // 2026-05-15: transcripts went polymorphic. older schemas had
    // call_id NOT NULL + run_id NOT NULL + FK to transcript_runs.
    if column_exists(db, "transcripts", "call_id").await? {
        // if it's still NOT NULL, relax it. ALTER MODIFY is idempotent.
        db.execute_unprepared("ALTER TABLE transcripts MODIFY COLUMN call_id BINARY(16) NULL")
            .await?;
    }
    if column_exists(db, "transcripts", "run_id").await? {
        if fk_exists(db, "transcripts", "fk_transcripts_run").await? {
            db.execute_unprepared("ALTER TABLE transcripts DROP FOREIGN KEY fk_transcripts_run")
                .await?;
        }
        db.execute_unprepared("ALTER TABLE transcripts DROP COLUMN run_id")
            .await?;
    }

    Ok(())
}

async fn create(db: &DatabaseConnection, table: &str, columns: &[&str]) -> Result<(), DbErr> {
    let body = columns.join(",\n  ");
    let sql = format!("CREATE TABLE IF NOT EXISTS `{table}` (\n  {body}\n) {DEFAULT_CHARSET}");
    db.execute_unprepared(&sql).await?;
    Ok(())
}

async fn column_exists(db: &DatabaseConnection, table: &str, column: &str) -> Result<bool, DbErr> {
    let backend = db.get_database_backend();
    let row = db
        .query_one_raw(Statement::from_sql_and_values(
            backend,
            "SELECT COUNT(*) AS cnt FROM information_schema.columns \
             WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?",
            [table.into(), column.into()],
        ))
        .await?;
    let count: i64 = row
        .map(|r| r.try_get::<i64>("", "cnt").unwrap_or(0))
        .unwrap_or(0);
    Ok(count > 0)
}

async fn fk_exists(db: &DatabaseConnection, table: &str, fk_name: &str) -> Result<bool, DbErr> {
    let backend = db.get_database_backend();
    let row = db
        .query_one_raw(Statement::from_sql_and_values(
            backend,
            "SELECT COUNT(*) AS cnt FROM information_schema.referential_constraints \
             WHERE constraint_schema = DATABASE() AND table_name = ? \
               AND constraint_name = ?",
            [table.into(), fk_name.into()],
        ))
        .await?;
    let count: i64 = row
        .map(|r| r.try_get::<i64>("", "cnt").unwrap_or(0))
        .unwrap_or(0);
    Ok(count > 0)
}

async fn create_index_if_missing(
    db: &DatabaseConnection,
    table: &str,
    index_name: &str,
    create_sql: &str,
) -> Result<(), DbErr> {
    let backend = db.get_database_backend();
    let row = db
        .query_one_raw(Statement::from_sql_and_values(
            backend,
            "SELECT COUNT(*) AS cnt FROM information_schema.statistics \
             WHERE table_schema = DATABASE() AND table_name = ? AND index_name = ?",
            [table.into(), index_name.into()],
        ))
        .await?;
    let count: i64 = row
        .map(|r| r.try_get::<i64>("", "cnt").unwrap_or(0))
        .unwrap_or(0);
    if count == 0 {
        db.execute_unprepared(create_sql).await?;
    }
    Ok(())
}
