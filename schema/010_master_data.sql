-- 010_master_data.sql  Owner: Kudrat
-- created_by/updated_by are nullable: system-loaded rows have no actor. FK to app_user added in 900_audit_fks.sql.

CREATE TABLE language (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code        varchar(10)  NOT NULL,
  name        varchar(100) NOT NULL,
  is_default  boolean      NOT NULL DEFAULT false,
  is_active   boolean      NOT NULL DEFAULT true,
  sort_order  integer      NOT NULL DEFAULT 0,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz  NOT NULL DEFAULT now(),
  updated_by    bigint,
  CONSTRAINT uq_language_code UNIQUE (code)
);
CREATE UNIQUE INDEX uq_language_is_default ON language (is_default) WHERE is_default;

CREATE TABLE currency (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code        char(3)      NOT NULL,
  name        varchar(100) NOT NULL,
  minor_unit  smallint     NOT NULL DEFAULT 2,
  is_active   boolean      NOT NULL DEFAULT true,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz  NOT NULL DEFAULT now(),
  updated_by    bigint,
  CONSTRAINT uq_currency_code UNIQUE (code),
  CONSTRAINT ck_currency_code_upper CHECK (code = upper(code)),
  CONSTRAINT ck_currency_minor_unit CHECK (minor_unit BETWEEN 0 AND 4)
);

CREATE TABLE country (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  iso2_code    char(2)      NOT NULL,
  iso3_code    char(3)      NOT NULL,
  name         varchar(150) NOT NULL,
  phone_code   varchar(8)   NOT NULL,
  currency_id  bigint,  -- nullable: some territories have no own currency in the source
  is_active    boolean      NOT NULL DEFAULT true,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz  NOT NULL DEFAULT now(),
  updated_by    bigint,
  CONSTRAINT uq_country_iso2_code UNIQUE (iso2_code),
  CONSTRAINT uq_country_iso3_code UNIQUE (iso3_code),
  CONSTRAINT fk_country_currency_id FOREIGN KEY (currency_id) REFERENCES currency (id) ON DELETE RESTRICT
);

CREATE TABLE state (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  country_id  bigint       NOT NULL,
  code        varchar(10),  -- nullable: not every source provides a state code
  name        varchar(150) NOT NULL,
  is_active   boolean      NOT NULL DEFAULT true,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz  NOT NULL DEFAULT now(),
  updated_by    bigint,
  CONSTRAINT fk_state_country_id FOREIGN KEY (country_id) REFERENCES country (id) ON DELETE RESTRICT,
  CONSTRAINT uq_state_country_id_name UNIQUE (country_id, name)
);

CREATE TABLE city (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  state_id    bigint       NOT NULL,
  name        varchar(150) NOT NULL,
  latitude    numeric(9,6),  -- nullable: source may lack coordinates. Source GeoNames, WGS84
  longitude   numeric(9,6),
  geoname_id  bigint,        -- nullable: manually added cities
  is_active   boolean      NOT NULL DEFAULT true,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz  NOT NULL DEFAULT now(),
  updated_by    bigint,
  CONSTRAINT fk_city_state_id FOREIGN KEY (state_id) REFERENCES state (id) ON DELETE RESTRICT,
  CONSTRAINT uq_city_geoname_id UNIQUE (geoname_id),
  CONSTRAINT ck_city_latitude CHECK (latitude BETWEEN -90 AND 90),
  CONSTRAINT ck_city_longitude CHECK (longitude BETWEEN -180 AND 180)
);
CREATE INDEX idx_city_state_id ON city (state_id);
CREATE INDEX idx_city_name_trgm ON city USING gin (name gin_trgm_ops);

-- Enumerations: one pattern for every fixed value set
CREATE TABLE reference_code_type (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code         varchar(60)  NOT NULL,
  description  varchar(255) NOT NULL,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz  NOT NULL DEFAULT now(),
  updated_by    bigint,
  CONSTRAINT uq_reference_code_type_code UNIQUE (code)
);

CREATE TABLE reference_code (
  id                      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reference_code_type_id  bigint      NOT NULL,
  code                    varchar(60) NOT NULL,
  is_active               boolean     NOT NULL DEFAULT true,
  sort_order              integer     NOT NULL DEFAULT 0,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz  NOT NULL DEFAULT now(),
  updated_by    bigint,
  CONSTRAINT fk_reference_code_reference_code_type_id FOREIGN KEY (reference_code_type_id)
    REFERENCES reference_code_type (id) ON DELETE RESTRICT,
  CONSTRAINT uq_reference_code_type_code_value UNIQUE (reference_code_type_id, code)
);

CREATE TABLE reference_code_translation (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reference_code_id  bigint       NOT NULL,
  language_id        bigint       NOT NULL,
  display_name       varchar(150) NOT NULL,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz  NOT NULL DEFAULT now(),
  updated_by    bigint,
  CONSTRAINT fk_reference_code_translation_reference_code_id FOREIGN KEY (reference_code_id)
    REFERENCES reference_code (id) ON DELETE CASCADE,
  CONSTRAINT fk_reference_code_translation_language_id FOREIGN KEY (language_id)
    REFERENCES language (id) ON DELETE RESTRICT,
  CONSTRAINT uq_reference_code_translation_code_language UNIQUE (reference_code_id, language_id)
);

-- UI labels: key + one translation row per language. Keys are never displayed.
CREATE TABLE ui_label (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  label_key  varchar(150) NOT NULL,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz  NOT NULL DEFAULT now(),
  updated_by    bigint,
  CONSTRAINT uq_ui_label_label_key UNIQUE (label_key)
);

CREATE TABLE ui_label_translation (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ui_label_id  bigint        NOT NULL,
  language_id  bigint        NOT NULL,
  label_text   varchar(1000) NOT NULL,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz  NOT NULL DEFAULT now(),
  updated_by    bigint,
  CONSTRAINT fk_ui_label_translation_ui_label_id FOREIGN KEY (ui_label_id) REFERENCES ui_label (id) ON DELETE CASCADE,
  CONSTRAINT fk_ui_label_translation_language_id FOREIGN KEY (language_id) REFERENCES language (id) ON DELETE RESTRICT,
  CONSTRAINT uq_ui_label_translation_label_language UNIQUE (ui_label_id, language_id)
);

CREATE TABLE skill (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name           varchar(200) NOT NULL,
  esco_uri       varchar(300),  -- nullable: custom skills have no ESCO id
  skill_type_id  bigint,        -- nullable: unclassified in source; reference_code of type skill_type
  is_active      boolean      NOT NULL DEFAULT true,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz  NOT NULL DEFAULT now(),
  updated_by    bigint,
  CONSTRAINT uq_skill_esco_uri UNIQUE (esco_uri),
  CONSTRAINT fk_skill_skill_type_id FOREIGN KEY (skill_type_id) REFERENCES reference_code (id) ON DELETE RESTRICT
);
CREATE INDEX idx_skill_name_trgm ON skill USING gin (name gin_trgm_ops);

CREATE TABLE skill_translation (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  skill_id      bigint       NOT NULL,
  language_id   bigint       NOT NULL,
  display_name  varchar(200) NOT NULL,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz  NOT NULL DEFAULT now(),
  updated_by    bigint,
  CONSTRAINT fk_skill_translation_skill_id FOREIGN KEY (skill_id) REFERENCES skill (id) ON DELETE CASCADE,
  CONSTRAINT fk_skill_translation_language_id FOREIGN KEY (language_id) REFERENCES language (id) ON DELETE RESTRICT,
  CONSTRAINT uq_skill_translation_skill_language UNIQUE (skill_id, language_id)
);

CREATE TABLE job_role (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name       varchar(200) NOT NULL,
  esco_uri   varchar(300),  -- nullable: custom roles
  is_active  boolean      NOT NULL DEFAULT true,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz  NOT NULL DEFAULT now(),
  updated_by    bigint,
  CONSTRAINT uq_job_role_esco_uri UNIQUE (esco_uri)
);
CREATE INDEX idx_job_role_name_trgm ON job_role USING gin (name gin_trgm_ops);

CREATE TABLE industry (
  id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  parent_industry_id  bigint,  -- nullable: top-level industries have no parent
  code                varchar(20)  NOT NULL,
  name                varchar(200) NOT NULL,
  is_active           boolean      NOT NULL DEFAULT true,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz  NOT NULL DEFAULT now(),
  updated_by    bigint,
  CONSTRAINT uq_industry_code UNIQUE (code),
  CONSTRAINT fk_industry_parent_industry_id FOREIGN KEY (parent_industry_id) REFERENCES industry (id) ON DELETE RESTRICT
);

CREATE TABLE qualification (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name         varchar(150) NOT NULL,
  isced_level  smallint,  -- nullable: some local qualifications are not mapped to ISCED
  sort_order   integer     NOT NULL DEFAULT 0,
  is_active    boolean     NOT NULL DEFAULT true,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz  NOT NULL DEFAULT now(),
  updated_by    bigint,
  CONSTRAINT uq_qualification_name UNIQUE (name),
  CONSTRAINT ck_qualification_isced_level CHECK (isced_level BETWEEN 0 AND 8)
);

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['language','currency','country','state','city','reference_code_type',
    'reference_code','reference_code_translation','ui_label','ui_label_translation','skill',
    'skill_translation','job_role','industry','qualification']
  LOOP
    EXECUTE format('CREATE TRIGGER trg_%1$s_updated_at BEFORE UPDATE ON %1$I
                    FOR EACH ROW EXECUTE FUNCTION set_updated_at()', t);
  END LOOP;
END $$;

-- Starting data. Extend as modules need new enumerations.
INSERT INTO language (code, name, is_default, sort_order) VALUES
 ('en','English',true,1),('hi','Hindi',false,2),('ta','Tamil',false,3),('te','Telugu',false,4);

INSERT INTO reference_code_type (code, description) VALUES
 ('employment_type','Permanent, contract, apprentice, etc.'),
 ('work_type','On-site, remote, hybrid'),
 ('job_category','Gig, staffing, permanent, apprentice, campus, consultant, managed remote'),
 ('application_status','Applied through joined or rejected'),
 ('skill_type','Technical, soft, language, tool'),
 ('verification_status','Pending, verified, rejected'),
 ('payment_status','Created, authorised, captured, failed, refunded'),
 ('session_status','Active, expired, revoked');

INSERT INTO reference_code (reference_code_type_id, code, sort_order)
SELECT t.id, v.code, v.ord FROM reference_code_type t
JOIN (VALUES
 ('application_status','applied',1),('application_status','shortlisted',2),
 ('application_status','interviewed',3),('application_status','offered',4),
 ('application_status','joined',5),('application_status','rejected',6),
 ('work_type','onsite',1),('work_type','remote',2),('work_type','hybrid',3),
 ('job_category','gig',1),('job_category','general_staffing',2),('job_category','professional_staffing',3),
 ('job_category','permanent',4),('job_category','apprentice',5),('job_category','campus_fresher',6),
 ('job_category','consultant_marketplace',7),('job_category','managed_remote',8),
 ('session_status','active',1),('session_status','expired',2),('session_status','revoked',3)
) AS v(type_code, code, ord) ON v.type_code = t.code;
