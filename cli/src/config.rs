//! on-disk config. lives at $XDG_CONFIG_HOME/sf-voice/config.toml (or the
//! platform default via the `dirs` crate). plain TOML, chmod 600 on
//! write — same posture as gh, aws-cli, kubectl. OS keyring lands later.

use std::{fs, path::PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Default, Deserialize, Serialize)]
pub struct Config {
    pub base_url: Option<String>,
    pub api_key: Option<String>,
    /// sticky project slug — used when a command omits --project.
    pub project: Option<String>,
}

pub fn config_path() -> Result<PathBuf> {
    let dir = dirs::config_dir().context("could not resolve config dir")?;
    Ok(dir.join("sf-voice").join("config.toml"))
}

pub fn load() -> Result<Config> {
    let path = config_path()?;
    if !path.exists() {
        return Ok(Config::default());
    }
    let text = fs::read_to_string(&path)
        .with_context(|| format!("reading {}", path.display()))?;
    toml::from_str(&text)
        .with_context(|| format!("parsing {}", path.display()))
}

pub fn save(cfg: &Config) -> Result<()> {
    let path = config_path()?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("creating {}", parent.display()))?;
    }
    let body = toml::to_string_pretty(cfg)?;
    fs::write(&path, body).with_context(|| format!("writing {}", path.display()))?;
    // tighten permissions on unix. windows ACLs are out of scope for v1.
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(&path)?.permissions();
        perms.set_mode(0o600);
        fs::set_permissions(&path, perms)?;
    }
    Ok(())
}
