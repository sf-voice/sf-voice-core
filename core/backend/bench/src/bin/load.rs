//! bench-load: write a fixed vector set into qdrant + clickhouse + duckdb.
//!
//! phase-0 stub. real impl lands in phase 2 once fastembed + bge-m3
//! produce vectors we can replay across stores.

use anyhow::Result;
use clap::Parser;

#[derive(Parser, Debug)]
#[command(name = "bench-load")]
struct Args {
    /// 'synthetic' (downloads a public embedding set) or 'real' (uses
    /// transcripts.parquet produced by the api after phase 2).
    #[arg(long, default_value = "synthetic")]
    source: String,

    /// number of vectors to load (synthetic only).
    #[arg(long, default_value_t = 100_000)]
    n: usize,
}

fn main() -> Result<()> {
    let args = Args::parse();
    eprintln!(
        "bench-load: phase 0 stub. source={} n={}",
        args.source, args.n
    );
    eprintln!("  real impl pending phase 2 (fastembed + bge-m3 + VectorStore trait).");
    Ok(())
}
