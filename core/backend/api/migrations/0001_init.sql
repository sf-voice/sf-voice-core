
CREATE TABLE orgs (
  id                  BINARY(16) PRIMARY KEY,
  name                VARCHAR(255) NOT NULL,
  slug                VARCHAR(64)  NOT NULL UNIQUE,
  bucket_name         VARCHAR(255),
  bucket_prefix       VARCHAR(512),
  bucket_region       VARCHAR(32),
  bucket_role_arn     VARCHAR(512),
  bucket_external_id  VARCHAR(128),
  config_repo_url     VARCHAR(512),
  slack_webhook_url   VARCHAR(512),
  created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                       ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE calls (
  id                  BINARY(16) PRIMARY KEY,
  org_id              BINARY(16) NOT NULL,
  external_id         VARCHAR(255),
  started_at          TIMESTAMP NOT NULL,
  ended_at            TIMESTAMP NULL,
  duration_ms         INT NULL,
  caller_number       VARCHAR(32),
  destination_number  VARCHAR(32),
  termination_reason  VARCHAR(64),
  audio_uri           VARCHAR(1024),
  caller_audio_uri    VARCHAR(1024),
  ai_audio_uri        VARCHAR(1024),
  created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                       ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_calls_org FOREIGN KEY (org_id) REFERENCES orgs(id),
  INDEX idx_calls_org_started (org_id, started_at DESC),
  INDEX idx_calls_external (org_id, external_id)
);

CREATE TABLE files (
  id              BINARY(16) PRIMARY KEY,
  org_id          BINARY(16) NOT NULL,
  call_id         BINARY(16) NULL,
  bucket          VARCHAR(255) NOT NULL,
  s3_key          VARCHAR(1024) NOT NULL,
  byte_size       BIGINT,
  content_type    VARCHAR(64),
  etag            VARCHAR(64),
  last_modified   TIMESTAMP NULL,
  ingested_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_files_org  FOREIGN KEY (org_id)  REFERENCES orgs(id),
  CONSTRAINT fk_files_call FOREIGN KEY (call_id) REFERENCES calls(id),
  -- s3_key can be much longer than what mysql allows in an index entry.
  -- under utf8mb4 (4 bytes/char) a composite key on bucket(255) +
  -- s3_key(N) maxes out at 3072 bytes, so N must be <= (3072-1020)/4
  -- = 513. 450 keeps comfortable headroom + handles 99%+ of real keys;
  -- the (bucket, s3_key) tuple is still globally unique because mysql
  -- enforces uniqueness on the indexed prefix.
  UNIQUE KEY uq_files_bucket_key (bucket, s3_key(450)),
  INDEX idx_files_org_ingested (org_id, ingested_at DESC),
  INDEX idx_files_call (call_id)
);

CREATE TABLE transcript_runs (
  id                 BINARY(16) PRIMARY KEY,
  call_id            BINARY(16) NOT NULL,
  status             ENUM('queued','running','done','failed') NOT NULL,
  whisper_model      VARCHAR(64),
  diarization_model  VARCHAR(64),
  vad_model          VARCHAR(64),
  triggered_by       VARCHAR(64) NOT NULL,
  error_message      TEXT,
  started_at         TIMESTAMP NULL,
  finished_at        TIMESTAMP NULL,
  created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_runs_call FOREIGN KEY (call_id) REFERENCES calls(id),
  INDEX idx_runs_call_created (call_id, created_at DESC),
  INDEX idx_runs_status (status)
);

CREATE TABLE transcripts (
  id             BIGINT PRIMARY KEY AUTO_INCREMENT,
  call_id        BINARY(16) NOT NULL,
  run_id         BINARY(16) NOT NULL,
  speaker_label  ENUM('ai','caller','unknown') NOT NULL,
  start_ms       INT NOT NULL,
  end_ms         INT NOT NULL,
  text           TEXT NOT NULL,
  confidence     FLOAT NULL,
  model_version  VARCHAR(64) NOT NULL,
  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_transcripts_call FOREIGN KEY (call_id) REFERENCES calls(id),
  CONSTRAINT fk_transcripts_run  FOREIGN KEY (run_id)  REFERENCES transcript_runs(id),
  INDEX idx_transcripts_call_start (call_id, start_ms),
  INDEX idx_transcripts_run (run_id),
  FULLTEXT KEY ftx_transcripts_text (text)
);

CREATE TABLE jobs (
  id               BINARY(16) PRIMARY KEY,
  org_id           BINARY(16) NOT NULL,
  kind             ENUM('ingest','transcribe','sandbox','open_pr') NOT NULL,
  subject_type     VARCHAR(32) NOT NULL,
  subject_id       BINARY(16) NULL,
  status           ENUM('queued','running','done','failed','cancelled') NOT NULL,
  payload          JSON NULL,
  result           JSON NULL,
  error_message    TEXT,
  progress_steps   JSON NULL,
  slack_thread_ts  VARCHAR(32),
  created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  started_at       TIMESTAMP NULL,
  finished_at      TIMESTAMP NULL,
  CONSTRAINT fk_jobs_org FOREIGN KEY (org_id) REFERENCES orgs(id),
  INDEX idx_jobs_status_kind (status, kind),
  INDEX idx_jobs_org_created (org_id, created_at DESC),
  INDEX idx_jobs_subject (subject_type, subject_id)
);

CREATE TABLE prompt_slices (
  id          BINARY(16) PRIMARY KEY,
  call_id     BINARY(16) NOT NULL,
  org_id      BINARY(16) NOT NULL,
  start_ms    INT NOT NULL,
  end_ms      INT NOT NULL,
  prompt_text TEXT NOT NULL,
  status      ENUM('draft','sandboxed','pr_open','merged','rejected') NOT NULL,
  job_id      BINARY(16) NULL,
  pr_url      VARCHAR(512),
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
               ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_slices_call FOREIGN KEY (call_id) REFERENCES calls(id),
  CONSTRAINT fk_slices_org  FOREIGN KEY (org_id)  REFERENCES orgs(id),
  CONSTRAINT fk_slices_job  FOREIGN KEY (job_id)  REFERENCES jobs(id),
  INDEX idx_slices_call (call_id),
  INDEX idx_slices_org_created (org_id, created_at DESC)
);
