import { useState, useEffect, useRef, useCallback } from "react";
import { createRoot } from "react-dom/client";

// ── types ─────────────────────────────────────────────────────────────────────

type MediaType = "video" | "audio";
type TaskStatus = "pending" | "indexing" | "ready" | "failed";
type MatchType  = "visual" | "conversation" | "text_in_video";

type Asset = {
  id: string;
  media_type: MediaType;
  status: TaskStatus;
  metadata?: { title?: string };
  duration_ms?: number;
  created_at: string;
};

type Task = {
  task_id: string;
  asset_id: string;
  status: TaskStatus;
  error?: string;
};

type SearchResult = {
  asset_id: string;
  score: number;
  start_ms: number;
  end_ms: number;
  match_type: MatchType;
  thumbnail_url?: string;
};

// ── helpers ───────────────────────────────────────────────────────────────────

function fmtMs(ms: number): string {
  const total = Math.max(0, ms);
  const m = Math.floor(total / 60_000);
  const s = ((total % 60_000) / 1000).toFixed(1).padStart(4, "0");
  return `${m}:${s}`;
}

function timeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  if (diff < 60_000)       return "just now";
  if (diff < 3_600_000)    return `${Math.floor(diff / 60_000)}m ago`;
  if (diff < 86_400_000)   return `${Math.floor(diff / 3_600_000)}h ago`;
  return `${Math.floor(diff / 86_400_000)}d ago`;
}

function dotClass(status: TaskStatus) {
  return `dot dot-${status}`;
}

// ── api helpers ───────────────────────────────────────────────────────────────

async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, init);
  const data = await res.json();
  if (!res.ok) throw new Error((data as any).error ?? `HTTP ${res.status}`);
  return data as T;
}

// ── app ───────────────────────────────────────────────────────────────────────

function App() {
  const [tab,            setTab]            = useState<"youtube" | "file">("youtube");
  const [youtubeUrl,     setYoutubeUrl]     = useState("");
  const [assets,         setAssets]         = useState<Asset[]>([]);
  // task_id → asset_id for active polling
  const [pollingTasks,   setPollingTasks]   = useState<Map<string, string>>(new Map());
  const [query,          setQuery]          = useState("");
  const [results,        setResults]        = useState<SearchResult[] | null>(null);
  const [ingestLoading,  setIngestLoading]  = useState(false);
  const [searchLoading,  setSearchLoading]  = useState(false);
  const [ingestError,    setIngestError]    = useState<string | null>(null);
  const [searchError,    setSearchError]    = useState<string | null>(null);
  const [isDragging,     setIsDragging]     = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // load all assets on mount
  useEffect(() => { loadAssets(); }, []);

  // poll pending/indexing tasks every 2s
  useEffect(() => {
    if (pollingTasks.size === 0) return;
    const timer = setInterval(async () => {
      const tasks = await Promise.all(
        [...pollingTasks.keys()].map(id =>
          fetch(`/api/tasks/${id}`).then(r => r.json() as Promise<Task>)
        )
      );
      let anyDone = false;
      for (const task of tasks) {
        if (task.status === "ready" || task.status === "failed") {
          setPollingTasks(prev => { const m = new Map(prev); m.delete(task.task_id); return m; });
          anyDone = true;
        } else {
          setAssets(prev => prev.map(a => a.id === task.asset_id ? { ...a, status: task.status } : a));
        }
      }
      if (anyDone) loadAssets();
    }, 2000);
    return () => clearInterval(timer);
  }, [pollingTasks]);

  async function loadAssets() {
    try {
      const data = await apiFetch<{ items: Asset[] }>("/api/assets");
      setAssets(data.items);
    } catch { /* silently ignore list errors */ }
  }

  function registerTask(assetId: string, taskId: string, optimistic: Partial<Asset>) {
    setAssets(prev => {
      const exists = prev.find(a => a.id === assetId);
      if (exists) return prev;
      return [{ id: assetId, media_type: "video", status: "pending", created_at: new Date().toISOString(), ...optimistic }, ...prev];
    });
    setPollingTasks(prev => new Map(prev).set(taskId, assetId));
  }

  async function ingestYoutube() {
    if (!youtubeUrl.trim()) return;
    setIngestLoading(true);
    setIngestError(null);
    try {
      const data = await apiFetch<{ asset_id: string; task_id: string }>("/api/ingest/youtube", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ url: youtubeUrl }),
      });
      setYoutubeUrl("");
      registerTask(data.asset_id, data.task_id, { media_type: "video" });
    } catch (e: any) {
      setIngestError(e.message);
    } finally {
      setIngestLoading(false);
    }
  }

  async function ingestFile(file: File) {
    setIngestLoading(true);
    setIngestError(null);
    try {
      const form = new FormData();
      form.append("file", file);
      form.append("title", file.name);
      const data = await apiFetch<{ asset_id: string; task_id: string }>("/api/ingest/file", {
        method: "POST",
        body: form,
      });
      registerTask(data.asset_id, data.task_id, {
        media_type: file.type.startsWith("audio/") ? "audio" : "video",
        metadata: { title: file.name },
      });
    } catch (e: any) {
      setIngestError(e.message);
    } finally {
      setIngestLoading(false);
    }
  }

  async function search() {
    if (!query.trim()) return;
    setSearchLoading(true);
    setSearchError(null);
    setResults(null);
    try {
      const data = await apiFetch<{ results: SearchResult[] }>("/api/search", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query }),
      });
      setResults(data.results ?? []);
    } catch (e: any) {
      setSearchError(e.message);
    } finally {
      setSearchLoading(false);
    }
  }

  async function deleteAsset(id: string) {
    setAssets(prev => prev.filter(a => a.id !== id));
    await fetch(`/api/assets/${id}`, { method: "DELETE" });
  }

  const onDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
    const file = e.dataTransfer.files[0];
    if (file) ingestFile(file);
  }, []);

  const assetById = (id: string) => assets.find(a => a.id === id);

  return (
    <div className="app">
      <header>
        <span className="logo">sf-voice</span>
        <span className="logo-sep">/</span>
        <span className="logo-sub">media demo</span>
      </header>

      <main>
        {/* ── left: ingest + assets ──────────────────────── */}
        <div className="col">

          <section>
            <p className="section-title">ingest</p>

            <div className="tabs">
              <button className={`tab${tab === "youtube" ? " active" : ""}`} onClick={() => setTab("youtube")}>
                youtube
              </button>
              <button className={`tab${tab === "file" ? " active" : ""}`} onClick={() => setTab("file")}>
                file
              </button>
            </div>

            {tab === "youtube" && (
              <div className="field">
                <input
                  type="url"
                  value={youtubeUrl}
                  onChange={e => setYoutubeUrl(e.target.value)}
                  onKeyDown={e => e.key === "Enter" && ingestYoutube()}
                  placeholder="https://youtube.com/watch?v=..."
                  disabled={ingestLoading}
                />
                <button
                  className="btn btn-primary"
                  onClick={ingestYoutube}
                  disabled={ingestLoading || !youtubeUrl.trim()}
                >
                  {ingestLoading ? "downloading…" : "ingest"}
                </button>
                <p className="hint">requires <code>yt-dlp</code> in PATH</p>
              </div>
            )}

            {tab === "file" && (
              <>
                <div
                  className={`drop-zone${isDragging ? " dragging" : ""}`}
                  onDragOver={e => { e.preventDefault(); setIsDragging(true); }}
                  onDragLeave={() => setIsDragging(false)}
                  onDrop={onDrop}
                  onClick={() => !ingestLoading && fileInputRef.current?.click()}
                >
                  <span className="drop-icon">↑</span>
                  {ingestLoading
                    ? <span>uploading…</span>
                    : <>
                        <span>drop audio or video here</span>
                        <span className="muted" style={{ fontSize: 12 }}>or click to browse</span>
                      </>
                  }
                </div>
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="video/*,audio/*"
                  style={{ display: "none" }}
                  onChange={e => { const f = e.target.files?.[0]; if (f) ingestFile(f); e.target.value = ""; }}
                />
              </>
            )}

            {ingestError && <p className="error-msg">{ingestError}</p>}
          </section>

          <section>
            <p className="section-title">
              assets
              <span className="count">{assets.length}</span>
            </p>

            {assets.length === 0
              ? <p className="empty">no assets yet</p>
              : (
                <ul className="asset-list">
                  {assets.map(asset => (
                    <li key={asset.id} className="asset-card">
                      <div className="status-row">
                        <span className={dotClass(asset.status)} />
                        <span className="status-text">{asset.status}</span>
                      </div>
                      <div className="asset-body">
                        <p className="asset-title">
                          {asset.metadata?.title ?? asset.id.slice(0, 14) + "…"}
                        </p>
                        <p className="asset-meta">
                          {asset.media_type}
                          {asset.duration_ms != null ? ` · ${fmtMs(asset.duration_ms)}` : ""}
                          {" · " + timeAgo(asset.created_at)}
                        </p>
                      </div>
                      <button
                        className="delete-btn"
                        onClick={() => deleteAsset(asset.id)}
                        title="delete asset"
                      >
                        ×
                      </button>
                    </li>
                  ))}
                </ul>
              )
            }
          </section>
        </div>

        {/* ── right: search + results ────────────────────── */}
        <div className="col">
          <section>
            <p className="section-title">search</p>

            <div className="search-row">
              <input
                type="text"
                value={query}
                onChange={e => setQuery(e.target.value)}
                onKeyDown={e => e.key === "Enter" && search()}
                placeholder='someone mentions the product roadmap…'
              />
              <button
                className="btn btn-primary"
                onClick={search}
                disabled={searchLoading || !query.trim()}
              >
                {searchLoading ? "…" : "search"}
              </button>
            </div>

            {searchError && <p className="error-msg" style={{ marginTop: 10 }}>{searchError}</p>}

            {results === null && !searchLoading && !searchError && (
              <p className="search-hint" style={{ marginTop: 14 }}>
                indexes audio, video, and on-screen text — try{" "}
                <em>"someone says hello"</em> or{" "}
                <em>"the word exit appears on screen"</em>
              </p>
            )}

            {results !== null && results.length === 0 && (
              <p className="empty" style={{ marginTop: 14 }}>no results</p>
            )}

            {results !== null && results.length > 0 && (
              <ul className="result-list" style={{ marginTop: 14 }}>
                {results.map((r, i) => {
                  const asset = assetById(r.asset_id);
                  return (
                    <li key={i} className="result-card">
                      <div className="result-header">
                        <span className={`match-badge match-${r.match_type}`}>
                          {r.match_type.replace(/_/g, " ")}
                        </span>
                        <span className="result-time">
                          {fmtMs(r.start_ms)} – {fmtMs(r.end_ms)}
                        </span>
                        <span className="result-score">
                          {Math.round(r.score * 100)}%
                        </span>
                      </div>
                      {asset && (
                        <p className="result-asset-name">
                          {asset.metadata?.title ?? r.asset_id.slice(0, 16) + "…"}
                        </p>
                      )}
                      {r.thumbnail_url && (
                        <img
                          src={r.thumbnail_url}
                          alt="match thumbnail"
                          className="result-thumb"
                        />
                      )}
                    </li>
                  );
                })}
              </ul>
            )}
          </section>
        </div>
      </main>
    </div>
  );
}

// ── mount ─────────────────────────────────────────────────────────────────────

const root = document.getElementById("root");
if (!root) throw new Error("missing #root");
createRoot(root).render(<App />);
