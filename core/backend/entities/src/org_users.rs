//! org_users: many-to-many between users and orgs, with a per-org role.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "org_users")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false, column_type = "Binary(16)")]
    pub id: Vec<u8>,

    #[sea_orm(column_type = "Binary(16)")]
    pub org_id: Vec<u8>,

    #[sea_orm(column_type = "Binary(16)", indexed)]
    pub user_id: Vec<u8>,

    #[sea_orm(
        column_type = "String(StringLen::N(16))",
        default_value = "member",
        comment = "'owner' | 'member'"
    )]
    pub role: String,

    pub created_at: DateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(
        belongs_to = "super::orgs::Entity",
        from = "Column::OrgId",
        to = "super::orgs::Column::Id",
        on_delete = "Cascade"
    )]
    Org,
    #[sea_orm(
        belongs_to = "super::users::Entity",
        from = "Column::UserId",
        to = "super::users::Column::Id",
        on_delete = "Cascade"
    )]
    User,
}

impl Related<super::orgs::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Org.def()
    }
}

impl Related<super::users::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::User.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}
