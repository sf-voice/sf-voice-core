//! chat_messages: one row per turn within a chat_thread. citations
//! carry retrieved-chunk references; pending_doc_ids tracks async
//! uploads still being indexed when the message was sent — resolved
//! out of this list as their embed_document jobs finish.

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel)]
#[sea_orm(table_name = "chat_messages")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false, column_type = "Binary(16)")]
    pub id: Vec<u8>,

    #[sea_orm(column_type = "Binary(16)", indexed)]
    pub thread_id: Vec<u8>,

    #[sea_orm(
        column_type = "String(StringLen::N(16))",
        comment = "'user' | 'assistant'"
    )]
    pub role: String,

    #[sea_orm(column_type = "Text")]
    pub content: String,

    // [{document_id, locator, score, text}]. always set, even if [].
    // application always provides — the table is new so NOT NULL JSON
    // without a default is fine; no existing rows to migrate.
    #[sea_orm(column_type = "Json")]
    pub citations: Json,

    // doc ids the user attached but were still indexing when posted.
    #[sea_orm(column_type = "Json")]
    pub pending_doc_ids: Json,

    pub created_at: DateTime,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(
        belongs_to = "super::chat_threads::Entity",
        from = "Column::ThreadId",
        to = "super::chat_threads::Column::Id"
    )]
    Thread,
}

impl Related<super::chat_threads::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Thread.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}
