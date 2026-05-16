//! prompt_slices: 'select range, insert prompt' artifact. one row per
//! human-authored intervention against a transcript timeline.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "prompt_slices")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false, column_type = "Binary(16)")]
    pub id: Vec<u8>,

    #[sea_orm(column_type = "Binary(16)", indexed)]
    pub call_id: Vec<u8>,

    #[sea_orm(column_type = "Binary(16)")]
    pub org_id: Vec<u8>,

    pub start_ms: i32,
    pub end_ms: i32,

    #[sea_orm(column_type = "Text")]
    pub prompt_text: String,

    #[sea_orm(
        column_type = "String(StringLen::N(32))",
        comment = "'draft' | 'sandboxed' | 'pr_open' | 'merged' | 'rejected'"
    )]
    pub status: String,

    // active sandbox job, if any
    #[sea_orm(column_type = "Binary(16)", nullable)]
    pub job_id: Option<Vec<u8>>,

    #[sea_orm(column_type = "String(StringLen::N(512))", nullable)]
    pub pr_url: Option<String>,

    pub created_at: DateTime,

    pub updated_at: DateTime,
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
        belongs_to = "super::orgs::Entity",
        from = "Column::OrgId",
        to = "super::orgs::Column::Id"
    )]
    Org,
    #[sea_orm(
        belongs_to = "super::jobs::Entity",
        from = "Column::JobId",
        to = "super::jobs::Column::Id"
    )]
    Job,
}

impl Related<super::calls::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Call.def()
    }
}

impl Related<super::orgs::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Org.def()
    }
}

impl Related<super::jobs::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Job.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}
