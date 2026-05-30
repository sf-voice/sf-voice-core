//! subcommand dispatch. each top-level command resolves auth + base_url
//! against (flag → env → config) and prints either a human view or
//! `--json` shape.

use std::fmt;
use std::io::{self, BufRead, Write};

use anyhow::{anyhow, Context, Result};
use clap::{Args, Subcommand};
use serde::{Deserialize, Serialize};

use sf_voice_media::{
    types::{IngestRequest, MediaKind, SearchRequest},
    SfVoiceMedia,
};

use crate::{config, http::ApiClient, output::emit};

const DEFAULT_BASE_URL: &str = "https://api.sf-voice.com";

#[derive(Subcommand, Debug)]
pub enum Command {
    /// print which API key + org you're acting as.
    Whoami,
    /// manage projects under the current org.
    #[command(subcommand)]
    Projects(ProjectsCmd),
    /// submit a URL or s3 key for ingestion.
    Ingest(IngestArgs),
    /// text-search across a project's transcripts.
    Search(SearchArgs),
    /// inspect jobs.
    #[command(subcommand)]
    Jobs(JobsCmd),
    /// list, get, delete documents.
    #[command(subcommand)]
    Documents(DocumentsCmd),
    /// manage sticky config (project, base URL, api key).
    #[command(subcommand)]
    Config(ConfigCmd),
}

#[derive(Subcommand, Debug)]
pub enum ProjectsCmd {
    List,
    Show {
        slug: String,
    },
    Create {
        name: String,
        #[arg(long)]
        slug: Option<String>,
        #[arg(long)]
        use_case: Option<String>,
    },
}

#[derive(Subcommand, Debug)]
pub enum JobsCmd {
    Get {
        job_id: String,
    },
    Poll {
        job_id: String,
        #[arg(long, default_value_t = 2)]
        interval_secs: u64,
        #[arg(long, default_value_t = 300)]
        timeout_secs: u64,
    },
}

#[derive(Subcommand, Debug)]
pub enum DocumentsCmd {
    List {
        #[arg(long)]
        project: Option<String>,
        #[arg(long, default_value_t = 1)]
        page: u32,
        #[arg(long, default_value_t = 20)]
        limit: u32,
    },
    Get {
        id: String,
    },
    Delete {
        id: String,
    },
}

#[derive(Subcommand, Debug)]
pub enum ConfigCmd {
    /// show the resolved config file contents.
    Show,
    /// set a single key. value '' clears the field.
    Set { key: String, value: String },
}

#[derive(Args, Debug)]
pub struct IngestArgs {
    /// public URL or s3:// uri. s3:// uris route through --source s3.
    pub source: String,
    /// project slug under the authenticated org. falls back to the
    /// sticky config value.
    #[arg(long)]
    pub project: Option<String>,
    #[arg(long, value_enum)]
    pub media_kind: Option<MediaKindArg>,
}

#[derive(Args, Debug)]
pub struct SearchArgs {
    pub query: String,
    #[arg(long)]
    pub project: Option<String>,
    #[arg(long, default_value_t = 1)]
    pub page: u32,
    #[arg(long, default_value_t = 10)]
    pub limit: u32,
}

#[derive(clap::ValueEnum, Debug, Clone, Copy)]
pub enum MediaKindArg {
    Video,
    Audio,
}

impl From<MediaKindArg> for MediaKind {
    fn from(v: MediaKindArg) -> Self {
        match v {
            MediaKindArg::Video => MediaKind::Video,
            MediaKindArg::Audio => MediaKind::Audio,
        }
    }
}

// ── dispatch ───────────────────────────────────────────────────────────────

pub async fn run(
    command: Command,
    base_url_flag: &Option<String>,
    api_key_flag: &Option<String>,
    json: bool,
) -> Result<()> {
    match command {
        // config commands don't need auth.
        Command::Config(c) => return config_cmd(c, json),

        // everything else needs auth.
        cmd => {
            let (base_url, api_key) = resolve_auth(base_url_flag, api_key_flag)?;
            dispatch_authed(cmd, &base_url, &api_key, json).await
        }
    }
}

async fn dispatch_authed(
    command: Command,
    base_url: &str,
    api_key: &str,
    json: bool,
) -> Result<()> {
    let api = ApiClient::new(base_url, api_key)?;
    let sdk = SfVoiceMedia::new(base_url, api_key);

    match command {
        Command::Whoami => {
            let projects: Vec<ProjectRow> = api.get("/api/v1/projects").await?;
            let org_id = projects
                .first()
                .map(|p| p.org_id.clone())
                .unwrap_or_else(|| "unknown".into());
            emit(
                &WhoamiOut {
                    base_url: base_url.to_string(),
                    org_id,
                    project_count: projects.len(),
                },
                json,
            )?;
        }
        Command::Projects(ProjectsCmd::List) => {
            let projects: Vec<ProjectRow> = api.get("/api/v1/projects").await?;
            emit(&ProjectList(projects), json)?;
        }
        Command::Projects(ProjectsCmd::Show { slug }) => {
            let p: ProjectRow = api
                .get(&format!("/api/v1/projects/{}", urlencode(&slug)))
                .await?;
            emit(&p, json)?;
        }
        Command::Projects(ProjectsCmd::Create {
            name,
            slug,
            use_case,
        }) => {
            let body = CreateProjectBody {
                name,
                slug,
                use_case,
            };
            let p: ProjectRow = api.post("/api/v1/projects", &body).await?;
            emit(&p, json)?;
        }
        Command::Ingest(args) => {
            let project = pick_project(args.project)?;
            let mut req = if args.source.starts_with("s3://") {
                // strip the scheme; backend expects bare key.
                let key = args.source.trim_start_matches("s3://").to_string();
                IngestRequest::from_s3(key).project(&project)
            } else {
                IngestRequest::from_url(&args.source).project(&project)
            };
            if let Some(mk) = args.media_kind {
                req = req.media_type(mk.into());
            }
            let resp = sdk.ingest(&req).await?;
            emit(
                &IngestOut {
                    document_id: resp.document_id,
                    job_id: resp.job_id,
                    status: resp.status,
                },
                json,
            )?;
        }
        Command::Search(args) => {
            let project = pick_project(args.project)?;
            let req = SearchRequest::new(&args.query, &project)
                .page(args.page)
                .limit(args.limit);
            let resp = sdk.search(&req).await?;
            emit(&SearchOut(resp.results), json)?;
        }
        Command::Jobs(JobsCmd::Get { job_id }) => {
            let job = sdk.get_job(&job_id).await?;
            emit(&JobOut::from(job), json)?;
        }
        Command::Jobs(JobsCmd::Poll {
            job_id,
            interval_secs,
            timeout_secs,
        }) => {
            let job = sdk
                .poll_job(
                    &job_id,
                    std::time::Duration::from_secs(interval_secs),
                    std::time::Duration::from_secs(timeout_secs),
                )
                .await?;
            emit(&JobOut::from(job), json)?;
        }
        Command::Documents(DocumentsCmd::List {
            project,
            page,
            limit,
        }) => {
            let resp = sdk
                .list_documents(project.as_deref(), Some(page), Some(limit))
                .await?;
            emit(&DocumentListOut(resp.items), json)?;
        }
        Command::Documents(DocumentsCmd::Get { id }) => {
            let doc = sdk.get_document(&id).await?;
            emit(&DocumentOut(doc), json)?;
        }
        Command::Documents(DocumentsCmd::Delete { id }) => {
            sdk.delete_document(&id).await?;
            println!("deleted {id}");
        }

        Command::Config(_) => unreachable!("handled above"),
    }
    Ok(())
}

fn config_cmd(cmd: ConfigCmd, json: bool) -> Result<()> {
    let mut cfg = config::load()?;
    match cmd {
        ConfigCmd::Show => emit(&ConfigOut(&cfg), json)?,
        ConfigCmd::Set { key, value } => {
            let v = if value.is_empty() { None } else { Some(value) };
            match key.as_str() {
                "project" => cfg.project = v,
                "base_url" => cfg.base_url = v,
                "api_key" => cfg.api_key = v,
                other => {
                    return Err(anyhow!(
                        "unknown config key '{other}'. valid: project, base_url, api_key"
                    ));
                }
            }
            config::save(&cfg)?;
            println!("ok");
        }
    }
    Ok(())
}

// ── auth resolution ────────────────────────────────────────────────────────

fn resolve_auth(
    base_url_flag: &Option<String>,
    api_key_flag: &Option<String>,
) -> Result<(String, String)> {
    let cfg = config::load().unwrap_or_default();

    let base_url = base_url_flag
        .clone()
        .or(cfg.base_url.clone())
        .unwrap_or_else(|| DEFAULT_BASE_URL.to_string());

    let api_key = match api_key_flag.clone().or(cfg.api_key.clone()) {
        Some(k) if !k.trim().is_empty() => k,
        _ => prompt_for_api_key()?,
    };

    Ok((base_url, api_key))
}

fn prompt_for_api_key() -> Result<String> {
    eprintln!("no api key set. paste an sk_live_ key (or set $SF_VOICE_API_KEY).");
    eprint!("api key: ");
    io::stderr().flush().ok();
    let mut line = String::new();
    io::stdin()
        .lock()
        .read_line(&mut line)
        .context("reading api key from stdin")?;
    let key = line.trim().to_string();
    if key.is_empty() {
        return Err(anyhow!("no api key provided"));
    }
    // offer to persist — purely interactive, never on a script.
    eprint!("save to config? [y/N] ");
    io::stderr().flush().ok();
    let mut answer = String::new();
    io::stdin().lock().read_line(&mut answer).ok();
    if answer.trim().eq_ignore_ascii_case("y") {
        let mut cfg = config::load().unwrap_or_default();
        cfg.api_key = Some(key.clone());
        config::save(&cfg)?;
        eprintln!("saved to {}", config::config_path()?.display());
    }
    Ok(key)
}

fn pick_project(arg: Option<String>) -> Result<String> {
    if let Some(p) = arg {
        return Ok(p);
    }
    let cfg = config::load().unwrap_or_default();
    cfg.project.ok_or_else(|| {
        anyhow!("no project specified. pass --project <slug> or run `sf-voice config set project <slug>`")
    })
}

fn urlencode(s: &str) -> String {
    // small enough to inline; the SDK already pulls in reqwest which
    // pulls in url, but we don't depend on it directly here. ascii-only
    // slugs (per backend validate_slug) means no encoding is needed in
    // practice, but be safe in case future slug rules change.
    s.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c.to_string()
            } else {
                format!("%{:02X}", c as u32)
            }
        })
        .collect()
}

// ── wire shapes for v1/projects (not yet in the SDK) ──────────────────────

#[derive(Debug, Deserialize, Serialize)]
struct ProjectRow {
    id: String,
    org_id: String,
    name: String,
    slug: String,
    use_case: Option<String>,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Serialize)]
struct CreateProjectBody {
    name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    slug: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    use_case: Option<String>,
}

// ── display impls — human formatter ───────────────────────────────────────

impl fmt::Display for ProjectRow {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(f, "{}", self.name)?;
        writeln!(f, "  slug:        {}", self.slug)?;
        writeln!(f, "  id:          {}", self.id)?;
        writeln!(f, "  org_id:      {}", self.org_id)?;
        if let Some(uc) = &self.use_case {
            writeln!(f, "  use_case:    {uc}")?;
        }
        writeln!(f, "  created_at:  {}", self.created_at)?;
        write!(f, "  updated_at:  {}", self.updated_at)
    }
}

#[derive(Serialize)]
struct ProjectList(Vec<ProjectRow>);

impl fmt::Display for ProjectList {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.0.is_empty() {
            return write!(f, "(no projects)");
        }
        for p in &self.0 {
            writeln!(f, "{}\t{}", p.slug, p.name)?;
        }
        Ok(())
    }
}

#[derive(Serialize)]
struct WhoamiOut {
    base_url: String,
    org_id: String,
    project_count: usize,
}

impl fmt::Display for WhoamiOut {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(f, "base_url:      {}", self.base_url)?;
        writeln!(f, "org_id:        {}", self.org_id)?;
        write!(f, "project_count: {}", self.project_count)
    }
}

#[derive(Serialize)]
struct IngestOut {
    document_id: String,
    job_id: String,
    status: String,
}

impl fmt::Display for IngestOut {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(f, "document_id: {}", self.document_id)?;
        writeln!(f, "job_id:      {}", self.job_id)?;
        write!(f, "status:      {}", self.status)
    }
}

#[derive(Serialize)]
struct JobOut {
    job_id: String,
    document_id: Option<String>,
    status: String,
    error: Option<String>,
    created_at: String,
    completed_at: Option<String>,
}

impl From<sf_voice_media::types::Job> for JobOut {
    fn from(j: sf_voice_media::types::Job) -> Self {
        // serialize via serde to a string; cheap and avoids re-mapping.
        let status = serde_json::to_value(&j.status)
            .ok()
            .and_then(|v| v.as_str().map(|s| s.to_string()))
            .unwrap_or_else(|| format!("{:?}", j.status));
        Self {
            job_id: j.job_id,
            document_id: j.document_id,
            status,
            error: j.error,
            created_at: j.created_at,
            completed_at: j.completed_at,
        }
    }
}

impl fmt::Display for JobOut {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(f, "job_id:        {}", self.job_id)?;
        if let Some(d) = &self.document_id {
            writeln!(f, "document_id:   {d}")?;
        }
        writeln!(f, "status:        {}", self.status)?;
        if let Some(e) = &self.error {
            writeln!(f, "error:         {e}")?;
        }
        writeln!(f, "created_at:    {}", self.created_at)?;
        if let Some(c) = &self.completed_at {
            write!(f, "completed_at:  {c}")?;
        } else {
            write!(f, "completed_at:  —")?;
        }
        Ok(())
    }
}

#[derive(Serialize)]
struct DocumentOut(sf_voice_media::types::Document);

impl fmt::Display for DocumentOut {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let d = &self.0;
        writeln!(f, "id:           {}", d.id)?;
        writeln!(f, "media_kind:   {:?}", d.media_kind)?;
        writeln!(f, "source_kind:  {:?}", d.source_kind)?;
        if let Some(u) = &d.source_url {
            writeln!(f, "source_url:   {u}")?;
        }
        writeln!(f, "status:       {:?}", d.status)?;
        if let Some(ms) = d.duration_ms {
            writeln!(f, "duration_ms:  {ms}")?;
        }
        writeln!(f, "created_at:   {}", d.created_at)?;
        write!(f, "updated_at:   {}", d.updated_at)
    }
}

#[derive(Serialize)]
struct DocumentListOut(Vec<sf_voice_media::types::Document>);

impl fmt::Display for DocumentListOut {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.0.is_empty() {
            return write!(f, "(no documents)");
        }
        for d in &self.0 {
            writeln!(f, "{}\t{:?}\t{:?}", d.id, d.media_kind, d.status)?;
        }
        Ok(())
    }
}

#[derive(Serialize)]
struct SearchOut(Vec<sf_voice_media::types::SearchResult>);

impl fmt::Display for SearchOut {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.0.is_empty() {
            return write!(f, "(no matches)");
        }
        for r in &self.0 {
            writeln!(
                f,
                "{}  [{}ms..{}ms]  score={:.3}",
                r.document_id, r.start_ms, r.end_ms, r.score
            )?;
            writeln!(f, "  {}", r.text)?;
        }
        Ok(())
    }
}

struct ConfigOut<'a>(&'a config::Config);

impl<'a> Serialize for ConfigOut<'a> {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        self.0.serialize(s)
    }
}

impl<'a> fmt::Display for ConfigOut<'a> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(
            f,
            "base_url:  {}",
            self.0.base_url.as_deref().unwrap_or("(unset)")
        )?;
        writeln!(
            f,
            "project:   {}",
            self.0.project.as_deref().unwrap_or("(unset)")
        )?;
        write!(
            f,
            "api_key:   {}",
            if self.0.api_key.is_some() {
                "(set)"
            } else {
                "(unset)"
            }
        )
    }
}
