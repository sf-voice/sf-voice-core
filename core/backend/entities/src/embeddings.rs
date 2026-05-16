//! embeddings: one row per embedded chunk. the dense vector itself
//! lives in the chosen vector store (qdrant / clickhouse / duckdb);
//! this table is the metadata + lookup side. the row's own `id` is
//! the vector store id (uuid string in qdrant / clickhouse / duckdb),
//! so no separate `vector_id` column.
//!
//! `model` implies `dim` (bge-m3 = 1024), so dim is omitted. the
//! active vector store is a deploy-wide config, not per-row.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "embeddings")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false, column_type = "Binary(16)")]
    pub id: Vec<u8>,

    #[sea_orm(column_type = "Binary(16)", indexed)]
    pub document_id: Vec<u8>,

    pub chunk_index: i32,

    // only set for time-coded sources (audio / video / transcript).
    pub start_ms: Option<i32>,
    pub end_ms: Option<i32>,

    // per-source positional info: {page:N} | {sheet, rows:[s,e]}
    // | {file, lines:[s,e]} | {url, anchor} | {thread_id, turn}.
    #[sea_orm(column_type = "Json", nullable)]
    pub source_locator: Option<Json>,

    #[sea_orm(column_type = "Text")]
    pub text: String,

    // 'bge-m3' for now. tracked per-row so we can re-embed with a new
    // model later and tell rows apart by lineage.
    #[sea_orm(column_type = "String(StringLen::N(64))")]
    pub model: String,

    pub created_at: DateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(
        belongs_to = "super::documents::Entity",
        from = "Column::DocumentId",
        to = "super::documents::Column::Id"
    )]
    Document,
}

impl Related<super::documents::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Document.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}
