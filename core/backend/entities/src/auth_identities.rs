//! auth_identities: oauth subject mapping. reserved for phase H+1.
//! users.password_hash NULL + an auth_identities row of
//! {provider, subject} = oauth-only account.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "auth_identities")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false, column_type = "Binary(16)")]
    pub id: Vec<u8>,

    #[sea_orm(column_type = "Binary(16)")]
    pub user_id: Vec<u8>,

    #[sea_orm(column_type = "String(StringLen::N(32))")]
    pub provider: String,

    #[sea_orm(column_type = "String(StringLen::N(255))")]
    pub subject: String,

    #[sea_orm(column_type = "String(StringLen::N(254))", nullable)]
    pub email: Option<String>,

    pub created_at: DateTime,
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
}

impl Related<super::users::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::User.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}
