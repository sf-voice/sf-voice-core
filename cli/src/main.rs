//! sf-voice — CLI for the San Francisco Voice Company API.
//!
//! v1 surface (this PR):
//!   sf-voice whoami
//!   sf-voice projects list | show <slug> | create <name>
//!   sf-voice ingest <url> --project <slug> [--media-kind …]
//!   sf-voice search <query> --project <slug>
//!   sf-voice jobs get <job_id>
//!   sf-voice config set project <slug>
//!
//! auth resolution: --api-key flag > $SF_VOICE_API_KEY > stored config.
//! a missing key triggers interactive mode that asks the user to paste
//! a key. browser device-code login lands in a follow-up release.

mod commands;
mod config;
mod http;
mod output;

use anyhow::Result;
use clap::Parser;

#[derive(Parser, Debug)]
#[command(
    name = "sf-voice",
    version,
    about = "CLI for the San Francisco Voice Company API",
    propagate_version = true
)]
struct Cli {
    /// override the base URL. defaults to https://api.sf-voice.com or
    /// $SF_VOICE_BASE_URL.
    #[arg(long, global = true, env = "SF_VOICE_BASE_URL")]
    base_url: Option<String>,

    /// override the API key. defaults to $SF_VOICE_API_KEY or the
    /// key saved by a previous interactive prompt.
    #[arg(long, global = true, env = "SF_VOICE_API_KEY", hide_env_values = true)]
    api_key: Option<String>,

    /// emit machine-readable JSON instead of human-formatted tables.
    #[arg(long, global = true)]
    json: bool,

    #[command(subcommand)]
    command: commands::Command,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    commands::run(cli.command, &cli.base_url, &cli.api_key, cli.json).await
}
