//! bench-query: run identical k-NN + filtered k-NN against each store,
//! emit p50/p95/p99 + recall@10 to `report.md`.
//!
//! phase-0 stub. real impl lands in phase 2.

use anyhow::Result;
use clap::Parser;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "bench-query")]
struct Args {
    /// newline-delimited query strings. embedded once via bge-m3 then
    /// fanned out to each store.
    #[arg(long)]
    queries: PathBuf,

    /// markdown output path.
    #[arg(long, default_value = "report.md")]
    report: PathBuf,
}

fn main() -> Result<()> {
    let args = Args::parse();
    eprintln!(
        "bench-query: phase 0 stub. queries={:?} report={:?}",
        args.queries, args.report
    );
    eprintln!("  real impl pending phase 2 (VectorStore trait + 3 backends).");
    Ok(())
}
