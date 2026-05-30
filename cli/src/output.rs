//! human-vs-json output. `--json` flag at the top level toggles between
//! a tight aligned plaintext view (default, friendly to grep + eyes)
//! and serde_json::to_string_pretty for piping.

use anyhow::Result;
use serde::Serialize;

pub fn emit<T: Serialize + Display>(value: &T, json: bool) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string_pretty(value)?);
    } else {
        println!("{value}");
    }
    Ok(())
}

pub use std::fmt::Display;
