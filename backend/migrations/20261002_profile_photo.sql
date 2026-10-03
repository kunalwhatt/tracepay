-- Applied automatically at API startup for existing PostgreSQL installations.
ALTER TABLE pilot_profiles ADD COLUMN IF NOT EXISTS gender VARCHAR(32) NOT NULL DEFAULT 'Prefer not to say';
ALTER TABLE pilot_profiles ADD COLUMN IF NOT EXISTS photo_storage_key TEXT;
ALTER TABLE pilot_profiles ADD COLUMN IF NOT EXISTS face_count INTEGER NOT NULL DEFAULT 0;
