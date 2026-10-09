-- Aucune donnée personnelle : empreintes SHA-256 d'UUID aléatoires, dates Europe/Paris sans heure.
CREATE TABLE IF NOT EXISTS installations (
  empreinte TEXT PRIMARY KEY,
  jour TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_installations_jour ON installations(jour);

CREATE TABLE IF NOT EXISTS presences (
  jour TEXT NOT NULL,
  empreinte TEXT NOT NULL,
  version TEXT NOT NULL,
  PRIMARY KEY (jour, empreinte)
);

CREATE TABLE IF NOT EXISTS jours_agreges (
  jour TEXT PRIMARY KEY,
  actifs INTEGER NOT NULL,
  nouvelles INTEGER NOT NULL
);
