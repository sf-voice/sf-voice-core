//! transcripts: one row per utterance/turn. polymorphic subject —
//! either call_id OR document_id is set (never both, never neither).
//! CHECK constraint enforced via apply_extras. no run grouping —
//! re-transcribing a subject is delete-then-insert; the audit trail
//! lives in `jobs`.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel)]
#[sea_orm(table_name = "transcripts")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i64,

    #[sea_orm(column_type = "Binary(16)", nullable)]
    pub call_id: Option<Vec<u8>>,

    #[sea_orm(column_type = "Binary(16)", nullable, indexed)]
    pub document_id: Option<Vec<u8>>,

    #[sea_orm(
        column_type = "String(StringLen::N(32))",
        comment = "calls: 'ai' | 'caller' | 'unknown'. documents: 'speaker_<n>' | 'speaker_unknown' (n is sherpa cluster id, scoped to one audio file)."
    )]
    pub speaker_label: String,

    pub start_ms: i32,
    pub end_ms: i32,

    #[sea_orm(column_type = "Text")]
    pub text: String,

    pub confidence: Option<f32>,

    // e.g. 'whisper-large-v3+pyannote-3.1'
    #[sea_orm(column_type = "String(StringLen::N(64))")]
    pub model_version: String,

    pub created_at: DateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(
        belongs_to = "super::calls::Entity",
        from = "Column::CallId",
        to = "super::calls::Column::Id"
    )]
    Call,
    #[sea_orm(
        belongs_to = "super::documents::Entity",
        from = "Column::DocumentId",
        to = "super::documents::Column::Id"
    )]
    Document,
}

impl Related<super::calls::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Call.def()
    }
}

impl Related<super::documents::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Document.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}
