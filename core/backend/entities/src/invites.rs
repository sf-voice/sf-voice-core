//! invites: pending org-membership invitations. accepted_at NULL until
//! the recipient redeems the token at /accept-invite/<token>.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "invites")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false, column_type = "Binary(16)")]
    pub id: Vec<u8>,

    #[sea_orm(column_type = "Binary(16)", indexed)]
    pub org_id: Vec<u8>,

    #[sea_orm(column_type = "String(StringLen::N(254))", indexed)]
    pub email: String,

    #[sea_orm(
        column_type = "String(StringLen::N(16))",
        default_value = "member",
        comment = "'owner' | 'member'"
    )]
    pub role: String,

    #[sea_orm(column_type = "String(StringLen::N(64))", unique)]
    pub token: String,

    #[sea_orm(column_type = "Binary(16)")]
    pub invited_by: Vec<u8>,

    pub accepted_at: Option<DateTime>,
    pub expires_at: DateTime,

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
        from = "Column::InvitedBy",
        to = "super::users::Column::Id"
    )]
    Inviter,
}

impl Related<super::orgs::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Org.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}
