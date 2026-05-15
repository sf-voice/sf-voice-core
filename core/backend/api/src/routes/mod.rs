//! /api/* route tree. each resource has its own file. composed here and
//! nested under /api in main.rs so the prefix lives in exactly one place.

use axum::Router;

use crate::state::AppState;

pub mod admin;
pub mod auth;
pub mod bucket;
pub mod calls;
// internal routes are bearer-token-gated and live OUTSIDE this router on
// purpose — they're mounted separately in main.rs so the customer-facing
// tree can never accidentally inherit them or vice versa.
pub mod internal;
pub mod jobs;
pub mod me;
pub mod orgs;
pub mod slices;
pub mod team;

pub fn router() -> Router<AppState> {
    Router::new()
        .merge(auth::router())
        .merge(bucket::router())
        .merge(calls::router())
        .merge(slices::router())
        .merge(jobs::router())
        .merge(orgs::router())
        .merge(team::router())
        .merge(me::router())
        .merge(admin::router())
}
