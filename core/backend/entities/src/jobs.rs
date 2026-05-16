//! jobs: async work units (ingest, transcribe, sandbox, open_pr,
//! youtube_ingest). a single in-process worker polls
//! status='queued' rows.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "jobs")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false, column_type = "Binary(16)")]
    pub id: Vec<u8>,

    #[sea_orm(column_type = "Binary(16)")]
    pub org_id: Vec<u8>,

    #[sea_orm(
        column_type = "String(StringLen::N(32))",
        comment = "'ingest' | 'transcribe' | 'transcribe_document' | 'sandbox' | 'open_pr' | 'youtube_ingest'"
    )]
    pub kind: String,

    // 'call' | 'file' | 'slice' | ...
    #[sea_orm(column_type = "String(StringLen::N(32))")]
    pub subject_type: String,

    #[sea_orm(column_type = "Binary(16)", nullable)]
    pub subject_id: Option<Vec<u8>>,

    #[sea_orm(
        column_type = "String(StringLen::N(32))",
        comment = "'queued' | 'running' | 'done' | 'failed' | 'cancelled'"
    )]
    pub status: String,

    #[sea_orm(column_type = "Json", nullable)]
    pub payload: Option<Json>,

    #[sea_orm(column_type = "Json", nullable)]
    pub result: Option<Json>,

    #[sea_orm(column_type = "Text", nullable)]
    pub error_message: Option<String>,

    // [{step, status, ts, detail?}] for the reasoning-path UI.
    #[sea_orm(column_type = "Json", nullable)]
    pub progress_steps: Option<Json>,

    #[sea_orm(column_type = "String(StringLen::N(32))", nullable)]
    pub slack_thread_ts: Option<String>,

    pub created_at: DateTime,

    pub started_at: Option<DateTime>,
    pub finished_at: Option<DateTime>,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(
        belongs_to = "super::orgs::Entity",
        from = "Column::OrgId",
        to = "super::orgs::Column::Id"
    )]
    Org,
}

impl Related<super::orgs::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Org.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}
