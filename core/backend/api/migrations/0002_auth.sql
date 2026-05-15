
CREATE TABLE users (
  id             BINARY(16) PRIMARY KEY,
  email          VARCHAR(254) NOT NULL UNIQUE,
  -- nullable on purpose: oauth-only users have no password. argon2id phc.
  password_hash  VARCHAR(255),
  display_name   VARCHAR(120),
  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                  ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE org_users (
  id          BINARY(16) PRIMARY KEY,
  org_id      BINARY(16) NOT NULL,
  user_id     BINARY(16) NOT NULL,
  role        ENUM('owner','member') NOT NULL DEFAULT 'member',
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_org_user (org_id, user_id),
  CONSTRAINT fk_org_users_org  FOREIGN KEY (org_id)  REFERENCES orgs(id)  ON DELETE CASCADE,
  CONSTRAINT fk_org_users_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_org_users_user (user_id)
);

-- session token = 32 random bytes stored as BINARY(32). cookie value is
-- the url-safe base64 of those bytes; lookup is by exact match. no
-- hashing in v1 — server-side token is unguessable; tighten later if
-- threat model demands it.
CREATE TABLE sessions (
  id              BINARY(32) PRIMARY KEY,
  user_id         BINARY(16) NOT NULL,
  -- mutable so the org switcher can update which org this session reads
  -- without forcing a re-login.
  current_org_id  BINARY(16) NOT NULL,
  expires_at      TIMESTAMP NOT NULL,
  created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_used_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                   ON UPDATE CURRENT_TIMESTAMP,
  ip              VARCHAR(45),
  user_agent      VARCHAR(255),
  CONSTRAINT fk_sessions_user FOREIGN KEY (user_id)        REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_sessions_org  FOREIGN KEY (current_org_id) REFERENCES orgs(id),
  INDEX idx_sessions_user (user_id),
  INDEX idx_sessions_expires (expires_at)
);

-- reserved for oauth (phase H+1). users.password_hash NULL + an
-- auth_identities row of {provider, subject} = oauth-only account.
CREATE TABLE auth_identities (
  id          BINARY(16) PRIMARY KEY,
  user_id     BINARY(16) NOT NULL,
  provider    VARCHAR(32)  NOT NULL,
  subject     VARCHAR(255) NOT NULL,
  email       VARCHAR(254),
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_identities_provider_subject (provider, subject),
  CONSTRAINT fk_identities_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- invites (phase I uses these — schema lands here so phase H doesn't
-- accumulate a half-finished table that needs a second migration).
CREATE TABLE invites (
  id           BINARY(16) PRIMARY KEY,
  org_id       BINARY(16) NOT NULL,
  email        VARCHAR(254) NOT NULL,
  role         ENUM('owner','member') NOT NULL DEFAULT 'member',
  -- url-safe random token; the accept URL is /accept-invite/<token>.
  token        VARCHAR(64) NOT NULL UNIQUE,
  invited_by   BINARY(16) NOT NULL,
  accepted_at  TIMESTAMP NULL,
  expires_at   TIMESTAMP NOT NULL,
  created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_invites_org     FOREIGN KEY (org_id)     REFERENCES orgs(id)  ON DELETE CASCADE,
  CONSTRAINT fk_invites_inviter FOREIGN KEY (invited_by) REFERENCES users(id),
  INDEX idx_invites_org   (org_id),
  INDEX idx_invites_email (email)
);
