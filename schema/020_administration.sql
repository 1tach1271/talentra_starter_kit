-- 020_administration.sql
-- Administration schema: 11 entities.

-- 1. Application users
CREATE TABLE app_user (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id uuid NOT NULL DEFAULT gen_random_uuid(),
  email varchar(254) NOT NULL,
  user_type_id bigint NOT NULL,
  status_id bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by bigint,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by bigint,
  deleted_at timestamptz,
  CONSTRAINT uq_app_user_public_id UNIQUE (public_id),
  CONSTRAINT uq_app_user_email UNIQUE (email),
  CONSTRAINT ck_app_user_email_lowercase CHECK (email = lower(email)),
  CONSTRAINT fk_app_user_user_type_id FOREIGN KEY (user_type_id)
    REFERENCES reference_code (id) ON DELETE RESTRICT,
  CONSTRAINT fk_app_user_status_id FOREIGN KEY (status_id)
    REFERENCES reference_code (id) ON DELETE RESTRICT
);

COMMENT ON COLUMN app_user.created_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';
COMMENT ON COLUMN app_user.updated_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';
COMMENT ON COLUMN app_user.deleted_at IS 'NULL while the account is active; populated for soft deletion.';

CREATE INDEX idx_app_user_status_id ON app_user (status_id);
CREATE INDEX idx_app_user_user_type_id ON app_user (user_type_id);

CREATE TRIGGER trg_app_user_updated_at
BEFORE UPDATE ON app_user
FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- 2. Role definitions
CREATE TABLE app_role (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code varchar(60) NOT NULL,
  description varchar(255) NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by bigint,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by bigint,
  CONSTRAINT uq_app_role_code UNIQUE (code)
);

COMMENT ON COLUMN app_role.created_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';
COMMENT ON COLUMN app_role.updated_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';

CREATE TRIGGER trg_app_role_updated_at
BEFORE UPDATE ON app_role
FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- 3. Permissions
CREATE TABLE permission (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code varchar(100) NOT NULL,
  description varchar(255) NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by bigint,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by bigint,
  CONSTRAINT uq_permission_code UNIQUE (code)
);

COMMENT ON COLUMN permission.created_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';
COMMENT ON COLUMN permission.updated_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';

CREATE TRIGGER trg_permission_updated_at
BEFORE UPDATE ON permission
FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- 4. Role-permission mapping
CREATE TABLE app_role_permission (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  app_role_id bigint NOT NULL,
  permission_id bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by bigint,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by bigint,
  CONSTRAINT fk_app_role_permission_app_role_id FOREIGN KEY (app_role_id)
    REFERENCES app_role (id) ON DELETE CASCADE,
  CONSTRAINT fk_app_role_permission_permission_id FOREIGN KEY (permission_id)
    REFERENCES permission (id) ON DELETE CASCADE,
  CONSTRAINT uq_app_role_permission_pair UNIQUE (app_role_id, permission_id)
);

COMMENT ON COLUMN app_role_permission.created_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';
COMMENT ON COLUMN app_role_permission.updated_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';

CREATE TRIGGER trg_app_role_permission_updated_at
BEFORE UPDATE ON app_role_permission
FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- 5. User-role assignments
CREATE TABLE app_user_role (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  app_user_id bigint NOT NULL,
  app_role_id bigint NOT NULL,
  effective_from timestamptz NOT NULL DEFAULT now(),
  effective_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by bigint,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by bigint,
  CONSTRAINT fk_app_user_role_app_user_id FOREIGN KEY (app_user_id)
    REFERENCES app_user (id) ON DELETE CASCADE,
  CONSTRAINT fk_app_user_role_app_role_id FOREIGN KEY (app_role_id)
    REFERENCES app_role (id) ON DELETE RESTRICT,
  CONSTRAINT ck_app_user_role_effective_dates
    CHECK (effective_until IS NULL OR effective_until > effective_from)
);

COMMENT ON COLUMN app_user_role.effective_until IS 'NULL when the assignment has no scheduled end date.';
COMMENT ON COLUMN app_user_role.created_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';
COMMENT ON COLUMN app_user_role.updated_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';

CREATE INDEX idx_app_user_role_app_user_id ON app_user_role (app_user_id);
CREATE INDEX idx_app_user_role_app_role_id ON app_user_role (app_role_id);

CREATE TRIGGER trg_app_user_role_updated_at
BEFORE UPDATE ON app_user_role
FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- 6. Credentials
CREATE TABLE credential (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  app_user_id bigint NOT NULL,
  authentication_method_id bigint NOT NULL,
  password_hash text,
  external_subject varchar(255),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by bigint,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by bigint,
  CONSTRAINT fk_credential_app_user_id FOREIGN KEY (app_user_id)
    REFERENCES app_user (id) ON DELETE CASCADE,
  CONSTRAINT fk_credential_authentication_method_id FOREIGN KEY (authentication_method_id)
    REFERENCES reference_code (id) ON DELETE RESTRICT,
  CONSTRAINT ck_credential_auth_data CHECK (
    (password_hash IS NOT NULL AND external_subject IS NULL)
    OR (password_hash IS NULL AND external_subject IS NOT NULL)
  )
);

COMMENT ON COLUMN credential.password_hash IS 'NULL for authentication methods that do not use a local password.';
COMMENT ON COLUMN credential.external_subject IS 'NULL for local-password credentials; otherwise stores the external identity subject.';
COMMENT ON COLUMN credential.created_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';
COMMENT ON COLUMN credential.updated_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';

CREATE INDEX idx_credential_app_user_id ON credential (app_user_id);

CREATE TRIGGER trg_credential_updated_at
BEFORE UPDATE ON credential
FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- 7. Consent records: append-only
CREATE TABLE consent_record (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  app_user_id bigint NOT NULL,
  purpose_id bigint NOT NULL,
  version varchar(60) NOT NULL,
  is_granted boolean NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by bigint,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by bigint,
  CONSTRAINT fk_consent_record_app_user_id FOREIGN KEY (app_user_id)
    REFERENCES app_user (id) ON DELETE RESTRICT,
  CONSTRAINT fk_consent_record_purpose_id FOREIGN KEY (purpose_id)
    REFERENCES reference_code (id) ON DELETE RESTRICT
);

COMMENT ON COLUMN consent_record.created_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';
COMMENT ON COLUMN consent_record.updated_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';

CREATE INDEX idx_consent_record_app_user_id ON consent_record (app_user_id);
CREATE INDEX idx_consent_record_purpose_id ON consent_record (purpose_id);

CREATE TRIGGER trg_consent_record_forbid_change
BEFORE UPDATE OR DELETE ON consent_record
FOR EACH ROW EXECUTE FUNCTION forbid_change();


-- 8. Identity sessions
CREATE TABLE identity_session (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id uuid NOT NULL DEFAULT gen_random_uuid(),
  app_user_id bigint NOT NULL,
  token_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  created_by bigint,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by bigint,
  CONSTRAINT uq_identity_session_public_id UNIQUE (public_id),
  CONSTRAINT uq_identity_session_token_hash UNIQUE (token_hash),
  CONSTRAINT fk_identity_session_app_user_id FOREIGN KEY (app_user_id)
    REFERENCES app_user (id) ON DELETE CASCADE,
  CONSTRAINT ck_identity_session_expiry CHECK (expires_at > created_at)
);

COMMENT ON COLUMN identity_session.revoked_at IS 'NULL while the session has not been revoked.';
COMMENT ON COLUMN identity_session.created_by IS 'Nullable for system-created sessions; FK added in schema/900_audit_fks.sql.';
COMMENT ON COLUMN identity_session.updated_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';

CREATE INDEX idx_identity_session_app_user_id ON identity_session (app_user_id);
CREATE INDEX idx_identity_session_expires_at ON identity_session (expires_at);

CREATE TRIGGER trg_identity_session_updated_at
BEFORE UPDATE ON identity_session
FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- 9. Audit events: append-only
CREATE TABLE audit_event (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_user_id bigint,
  event_code varchar(100) NOT NULL,
  entity_type varchar(100) NOT NULL,
  entity_id bigint,
  event_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by bigint,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by bigint,
  CONSTRAINT fk_audit_event_actor_user_id FOREIGN KEY (actor_user_id)
    REFERENCES app_user (id) ON DELETE SET NULL
);

COMMENT ON COLUMN audit_event.actor_user_id IS 'NULL when no application user can be identified.';
COMMENT ON COLUMN audit_event.entity_id IS 'NULL when the event is not associated with one specific entity.';
COMMENT ON COLUMN audit_event.created_by IS 'Nullable for system-generated events; FK added in schema/900_audit_fks.sql.';
COMMENT ON COLUMN audit_event.updated_by IS 'Nullable for system-generated events; FK added in schema/900_audit_fks.sql.';

CREATE INDEX idx_audit_event_actor_user_id ON audit_event (actor_user_id);
CREATE INDEX idx_audit_event_occurred_at ON audit_event (occurred_at);
CREATE INDEX idx_audit_event_entity ON audit_event (entity_type, entity_id);

CREATE TRIGGER trg_audit_event_forbid_change
BEFORE UPDATE OR DELETE ON audit_event
FOR EACH ROW EXECUTE FUNCTION forbid_change();


-- 10. Error logs: append-only
CREATE TABLE error_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  app_user_id bigint,
  error_code varchar(100) NOT NULL,
  message text NOT NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by bigint,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by bigint,
  CONSTRAINT fk_error_log_app_user_id FOREIGN KEY (app_user_id)
    REFERENCES app_user (id) ON DELETE SET NULL
);

COMMENT ON COLUMN error_log.app_user_id IS 'NULL for errors not associated with an authenticated user.';
COMMENT ON COLUMN error_log.created_by IS 'Nullable for system-generated logs; FK added in schema/900_audit_fks.sql.';
COMMENT ON COLUMN error_log.updated_by IS 'Nullable for system-generated logs; FK added in schema/900_audit_fks.sql.';

CREATE INDEX idx_error_log_occurred_at ON error_log (occurred_at);
CREATE INDEX idx_error_log_error_code ON error_log (error_code);

CREATE TRIGGER trg_error_log_forbid_change
BEFORE UPDATE OR DELETE ON error_log
FOR EACH ROW EXECUTE FUNCTION forbid_change();


-- 11. Blocking relationships
CREATE TABLE block_entry (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  blocker_user_id bigint NOT NULL,
  blocked_user_id bigint NOT NULL,
  reason varchar(255),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by bigint,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by bigint,
  deleted_at timestamptz,
  CONSTRAINT fk_block_entry_blocker_user_id FOREIGN KEY (blocker_user_id)
    REFERENCES app_user (id) ON DELETE RESTRICT,
  CONSTRAINT fk_block_entry_blocked_user_id FOREIGN KEY (blocked_user_id)
    REFERENCES app_user (id) ON DELETE RESTRICT,
  CONSTRAINT ck_block_entry_not_self CHECK (blocker_user_id <> blocked_user_id)
);

COMMENT ON COLUMN block_entry.reason IS 'NULL when no reason was provided.';
COMMENT ON COLUMN block_entry.created_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';
COMMENT ON COLUMN block_entry.updated_by IS 'Nullable until an actor is known; FK added in schema/900_audit_fks.sql.';
COMMENT ON COLUMN block_entry.deleted_at IS 'NULL while the block is active; populated when unblocked.';

CREATE INDEX idx_block_entry_blocker_user_id ON block_entry (blocker_user_id);
CREATE INDEX idx_block_entry_blocked_user_id ON block_entry (blocked_user_id);

CREATE TRIGGER trg_block_entry_updated_at
BEFORE UPDATE ON block_entry
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
