//! documents: unified playable-asset registry. self-referencing via
//! source_id models derivation chains — raw youtube mp4 (parent) →
//! video.mp4 + audio.m4a + audio.wav (children).

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "documents")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false, column_type = "Binary(16)")]
    pub id: Vec<u8>,

    // ownership category. 'internal' for now; 'customer' reserved.
    #[sea_orm(
        column_type = "String(StringLen::N(32))",
        comment = "'internal' | 'customer' (reserved)"
    )]
    pub r#type: String,

    #[sea_orm(
        column_type = "String(StringLen::N(32))",
        comment = "'audio' | 'video' | 'image' | 'pdf' | 'spreadsheet' | 'markdown' | 'code' | 'web_url' | 'chat_export' | 'transcript_segment'"
    )]
    pub media_kind: String,

    #[sea_orm(
        column_type = "String(StringLen::N(64))",
        comment = "'youtube' | 'upload' | 'call' | ..."
    )]
    pub source_kind: String,

    // self-reference. NULL on top-level sources; non-NULL on derived
    // assets pointing back to the parent doc.
    #[sea_orm(column_type = "Binary(16)", nullable)]
    pub source_id: Option<Vec<u8>>,

    // original URL for top-level sources. NULL for derived assets
    // (they inherit context by walking source_id).
    #[sea_orm(column_type = "String(StringLen::N(1024))", nullable)]
    pub source_url: Option<String>,

    // s3 location. nullable until upload completes.
    #[sea_orm(column_type = "String(StringLen::N(255))", nullable)]
    pub bucket: Option<String>,

    #[sea_orm(column_type = "String(StringLen::N(1024))", nullable)]
    pub s3_key: Option<String>,

    // mirrors basename of s3_key but kept separate so renames don't
    // touch s3.
    #[sea_orm(column_type = "String(StringLen::N(255))", nullable)]
    pub filename: Option<String>,

    #[sea_orm(column_type = "String(StringLen::N(64))", nullable)]
    pub mime_type: Option<String>,

    pub duration_ms: Option<i32>,

    // job state for THIS doc. derived docs land as 'ready'; parents
    // walk queued → downloading → extracting → uploading → ready.
    #[sea_orm(
        column_type = "String(StringLen::N(32))",
        indexed,
        comment = "'queued' | 'downloading' | 'extracting' | 'uploading' | 'ready' | 'failed'"
    )]
    pub processing_status: String,

    #[sea_orm(column_type = "Text", nullable)]
    pub processing_error: Option<String>,

    #[sea_orm(column_type = "Binary(16)", nullable)]
    pub job_id: Option<Vec<u8>>,

    #[sea_orm(column_type = "String(StringLen::N(512))", nullable)]
    pub title: Option<String>,

    // hierarchical organisation. single varchar with '/'-separated path
    // (e.g. '/internal/ml/3blue1brown'). nullable so schema-sync can add
    // this column to existing rows; application reads None as "/".
    #[sea_orm(column_type = "String(StringLen::N(512))", nullable, indexed)]
    pub folder: Option<String>,

    // freeform labels. nullable for the same reason; application reads
    // None as the empty array.
    #[sea_orm(column_type = "Json", nullable)]
    pub tags: Option<Json>,

    pub created_at: DateTime,

    pub updated_at: DateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    // self-reference for derivation chains.
    #[sea_orm(belongs_to = "Entity", from = "Column::SourceId", to = "Column::Id")]
    Source,
}

impl ActiveModelBehavior for ActiveModel {}
