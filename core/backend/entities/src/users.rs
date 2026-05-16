//! users: single human across all orgs. password_hash nullable so
//! oauth-only accounts (auth_identities row, no password) work.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "users")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false, column_type = "Binary(16)")]
    pub id: Vec<u8>,

    #[sea_orm(column_type = "String(StringLen::N(254))", unique)]
    pub email: String,

    // argon2id phc string. nullable for oauth-only users.
    #[sea_orm(column_type = "String(StringLen::N(255))", nullable)]
    pub password_hash: Option<String>,

    #[sea_orm(column_type = "String(StringLen::N(120))", nullable)]
    pub display_name: Option<String>,

    pub created_at: DateTime,

    pub updated_at: DateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
