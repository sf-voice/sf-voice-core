//! orgs: customer organisations. holds bucket-credential state +
//! per-org slack/config-repo wiring.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "orgs")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false, column_type = "Binary(16)")]
    pub id: Vec<u8>,

    #[sea_orm(column_type = "String(StringLen::N(255))")]
    pub name: String,

    #[sea_orm(column_type = "String(StringLen::N(64))", unique)]
    pub slug: String,

    #[sea_orm(column_type = "String(StringLen::N(255))", nullable)]
    pub bucket_name: Option<String>,

    #[sea_orm(column_type = "String(StringLen::N(512))", nullable)]
    pub bucket_prefix: Option<String>,

    #[sea_orm(column_type = "String(StringLen::N(32))", nullable)]
    pub bucket_region: Option<String>,

    #[sea_orm(column_type = "String(StringLen::N(512))", nullable)]
    pub bucket_role_arn: Option<String>,

    #[sea_orm(column_type = "String(StringLen::N(128))", nullable)]
    pub bucket_external_id: Option<String>,

    #[sea_orm(
        column_type = "String(StringLen::N(16))",
        nullable,
        comment = "'role' | 'keys'"
    )]
    pub bucket_auth_method: Option<String>,

    #[sea_orm(column_type = "String(StringLen::N(128))", nullable)]
    pub bucket_access_key_id: Option<String>,

    #[sea_orm(column_type = "VarBinary(StringLen::N(512))", nullable)]
    pub bucket_secret_access_key_encrypted: Option<Vec<u8>>,

    pub bucket_verified_at: Option<DateTime>,

    // 12-digit AWS account id, persisted as a draft on /api/org/bucket/setup.
    #[sea_orm(column_type = "String(StringLen::N(16))", nullable)]
    pub bucket_account_id: Option<String>,

    #[sea_orm(column_type = "String(StringLen::N(512))", nullable)]
    pub config_repo_url: Option<String>,

    #[sea_orm(column_type = "String(StringLen::N(512))", nullable)]
    pub slack_webhook_url: Option<String>,

    pub created_at: DateTime,

    pub updated_at: DateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
