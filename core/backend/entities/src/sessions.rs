//! sessions: 32-byte random token (BINARY(32)) is the cookie value
//! base64'd. server stores raw bytes; lookup is exact match. no
//! hashing in v1 — token is unguessable.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "sessions")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false, column_type = "Binary(32)")]
    pub id: Vec<u8>,

    #[sea_orm(column_type = "Binary(16)", indexed)]
    pub user_id: Vec<u8>,

    // mutable so the org switcher can update the active org without
    // forcing a re-login.
    #[sea_orm(column_type = "Binary(16)")]
    pub current_org_id: Vec<u8>,

    #[sea_orm(indexed)]
    pub expires_at: DateTime,

    pub created_at: DateTime,

    pub last_used_at: DateTime,

    #[sea_orm(column_type = "String(StringLen::N(45))", nullable)]
    pub ip: Option<String>,

    #[sea_orm(column_type = "String(StringLen::N(255))", nullable)]
    pub user_agent: Option<String>,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(
        belongs_to = "super::users::Entity",
        from = "Column::UserId",
        to = "super::users::Column::Id",
        on_delete = "Cascade"
    )]
    User,
    #[sea_orm(
        belongs_to = "super::orgs::Entity",
        from = "Column::CurrentOrgId",
        to = "super::orgs::Column::Id"
    )]
    CurrentOrg,
}

impl Related<super::users::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::User.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}
