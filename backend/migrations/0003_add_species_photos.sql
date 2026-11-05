CREATE TABLE IF NOT EXISTS species_photos (
    species_key VARCHAR(180) PRIMARY KEY,
    species_name VARCHAR(150) NOT NULL,
    scientific_name VARCHAR(150) NOT NULL,
    photo_url VARCHAR(500) NOT NULL,
    verified_by_id INTEGER NOT NULL REFERENCES users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
