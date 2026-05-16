//! calls: one row per phone call. links audio files + transcript runs.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "calls")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false, column_type = "Binary(16)")]
    pub id: Vec<u8>,

    #[sea_orm(column_type = "Binary(16)", indexed)]
    pub org_id: Vec<u8>,

    // telnyx / sf-voice runtime id
    #[sea_orm(column_type = "String(StringLen::N(255))", nullable)]
    pub external_id: Option<String>,

    pub started_at: DateTime,
    pub ended_at: Option<DateTime>,
    pub duration_ms: Option<i32>,

    // e.164
    #[sea_orm(column_type = "String(StringLen::N(32))", nullable)]
    pub caller_number: Option<String>,

    #[sea_orm(column_type = "String(StringLen::N(32))", nullable)]
    pub destination_number: Option<String>,

    #[sea_orm(column_type = "String(StringLen::N(64))", nullable)]
    pub termination_reason: Option<String>,

    // mixed track if separated tracks unavailable
    #[sea_orm(column_type = "String(StringLen::N(1024))", nullable)]
    pub audio_uri: Option<String>,

    #[sea_orm(column_type = "String(StringLen::N(1024))", nullable)]
    pub caller_audio_uri: Option<String>,

    #[sea_orm(column_type = "String(StringLen::N(1024))", nullable)]
    pub ai_audio_uri: Option<String>,

    pub created_at: DateTime,

    pub updated_at: DateTime,
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
