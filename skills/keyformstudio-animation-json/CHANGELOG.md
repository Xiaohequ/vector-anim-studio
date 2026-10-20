# Journal du skill keyformstudio-animation-json

Le skill est versionné avec l'application : chaque entrée indique la version du
skill, la version VASF couverte et la version d'appli de référence.

## 1.0.0 — 2026-10-21

- Première version hébergée DANS le dépôt `vector-anim-studio` (auparavant
  uniquement dans le workspace de l'agent, sous
  `skills/keyformstudio-animation-json/`).
- Frontmatter enrichi : `version` (skill), `vasf` (version de format couverte),
  `app` (version d'appli de référence).
- Chemins réécrits pour le dépôt : la spec et les exemples cités sont ceux de
  `docs/` (source de vérité versionnée avec le code) ; `references/` devient un
  miroir de contrôle.
- Ajout de `scripts/sync_skill.sh` (copie vers le workspace de l'agent +
  vérification de dérive `references/` ↔ `docs/`).
- Alignement VASF-6 / app 0.39.0 : groupes d'éléments (`groups` + `groupId` par
  nom), transformation de groupe rendue autour du centre visuel, import strict
  des versions 1 à 6.
