-- Safe, idempotent PostgreSQL migration for Fernet-encrypted profile values.
-- The ciphertext is longer than the original plaintext, so these fields must not use short VARCHAR limits.
ALTER TABLE pilot_profiles
    ALTER COLUMN full_name TYPE TEXT,
    ALTER COLUMN date_of_birth TYPE TEXT,
    ALTER COLUMN bank_name TYPE TEXT,
    ALTER COLUMN account_last4 TYPE TEXT;
