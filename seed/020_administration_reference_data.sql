-- Administration reference-code categories and codes.
-- Uses code-based lookups; does not assume numeric IDs.

INSERT INTO reference_code_type (code, description)
VALUES
  ('user_type', 'Application account type'),
  ('account_status', 'Application account status'),
  ('authentication_method', 'Authentication method'),
  ('consent_purpose', 'Purpose for collecting consent')
ON CONFLICT (code) DO NOTHING;


-- User types
INSERT INTO reference_code (reference_code_type_id, code, sort_order)
SELECT rct.id, v.code, v.sort_order
FROM reference_code_type rct
JOIN (
  VALUES
    ('candidate', 1),
    ('employer', 2),
    ('recruiter', 3),
    ('consultant', 4),
    ('admin', 5),
    ('tpo', 6)
) AS v(code, sort_order) ON true
WHERE rct.code = 'user_type'
ON CONFLICT (reference_code_type_id, code) DO NOTHING;


-- Account statuses
INSERT INTO reference_code (reference_code_type_id, code, sort_order)
SELECT rct.id, v.code, v.sort_order
FROM reference_code_type rct
JOIN (
  VALUES
    ('active', 1),
    ('pending', 2),
    ('suspended', 3),
    ('deactivated', 4)
) AS v(code, sort_order) ON true
WHERE rct.code = 'account_status'
ON CONFLICT (reference_code_type_id, code) DO NOTHING;


-- Authentication methods
INSERT INTO reference_code (reference_code_type_id, code, sort_order)
SELECT rct.id, v.code, v.sort_order
FROM reference_code_type rct
JOIN (
  VALUES
    ('password', 1),
    ('google', 2),
    ('microsoft', 3)
) AS v(code, sort_order) ON true
WHERE rct.code = 'authentication_method'
ON CONFLICT (reference_code_type_id, code) DO NOTHING;


-- Consent purposes
INSERT INTO reference_code (reference_code_type_id, code, sort_order)
SELECT rct.id, v.code, v.sort_order
FROM reference_code_type rct
JOIN (
  VALUES
    ('terms_of_service', 1),
    ('privacy_policy', 2),
    ('marketing', 3)
) AS v(code, sort_order) ON true
WHERE rct.code = 'consent_purpose'
ON CONFLICT (reference_code_type_id, code) DO NOTHING;


-- English display names
INSERT INTO reference_code_translation
  (reference_code_id, language_id, display_name)
SELECT rc.id, l.id, v.display_name
FROM (
  VALUES
    ('user_type', 'candidate', 'Candidate'),
    ('user_type', 'employer', 'Employer'),
    ('user_type', 'recruiter', 'Recruiter'),
    ('user_type', 'consultant', 'Consultant'),
    ('user_type', 'admin', 'Administrator'),
    ('user_type', 'tpo', 'Placement Officer'),
    ('account_status', 'active', 'Active'),
    ('account_status', 'pending', 'Pending'),
    ('account_status', 'suspended', 'Suspended'),
    ('account_status', 'deactivated', 'Deactivated'),
    ('authentication_method', 'password', 'Password'),
    ('authentication_method', 'google', 'Google'),
    ('authentication_method', 'microsoft', 'Microsoft'),
    ('consent_purpose', 'terms_of_service', 'Terms of Service'),
    ('consent_purpose', 'privacy_policy', 'Privacy Policy'),
    ('consent_purpose', 'marketing', 'Marketing')
) AS v(type_code, value_code, display_name)
JOIN reference_code_type rct ON rct.code = v.type_code
JOIN reference_code rc
  ON rc.reference_code_type_id = rct.id
 AND rc.code = v.value_code
JOIN language l ON l.code = 'en'
ON CONFLICT (reference_code_id, language_id) DO NOTHING;
