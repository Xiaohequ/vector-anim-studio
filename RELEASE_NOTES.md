# Vector Anim Studio 0.12.0

## Nouveautés

- **Extensions du format d'échange « vasf-2 » (Groupe 1 — format seul)** : tout est
  développé À L'IMPORT, le moteur d'animation est inchangé ; un fichier `version: 1`
  reste importable tel quel, `version: 2` marque les fichiers qui utilisent les
  extensions.
  - **Couches multiples par forme** (`"layers": [...]`) : plusieurs primitives dans
    UNE forme (un visage avec yeux + bouche n'a plus besoin d'une forme par élément).
    Ordre de dessin = ordre du tableau ; chaque couche porte type/couleur/remplissage/
    épaisseur/taille/points + pose locale (`x`/`y` relatifs au centre de forme,
    rotation, échelle, opacité). Les `x/y/rotation/scale/opacity/keyframes` de la
    forme restent la pose du GROUPE. À l'export, une forme multi-couches émet
    `layers[]` (version 2), une forme à couche unique reste à plat (version 1).
  - **Palette d'alias** (`"theme": {"peau": "#FFE3C2", …}`) : toute couleur (fond,
    forme, couche, def) accepte `"$peau"` — retouche globale en 1 ligne ; alias
    inconnu = erreur collectée. L'export n'émet jamais de palette (couleurs
    développées).
  - **Cycles** (`"cycle": {"repeat": N}`) : le motif de keyframes est répété N fois
    de plus après la dernière, période = dernier − premier temps ; au raccord, la
    première keyframe répétée est sautée quand elle tombe sur un temps déjà posé
    (un motif bouclé donne une timeline propre). Disponible au niveau forme ET au
    niveau `skeleton` (répète tous les os — cycle de marche sans écrire 300
    keyframes). Sans keyframes, `cycle` est ignoré.
  - **Définitions réutilisables** (`"defs": {"oeil": {...}}` + `"ref": "oeil"`) :
    géométrie définie une fois, instanciée par forme ; la forme peut surcharger
    chaque champ (ex. œil droit rouge). Géométrie seule (pas de pose/temps dans une
    def), pas de refs imbriquées, `ref` au niveau forme uniquement.
- **Import** : erreurs toujours toutes collectées en français avec chemins précis
  (`theme.peau`, `shapes[0].layers[1].type`, `defs.oeil.type`, `shapes[1].ref`,
  `shapes[0].cycle.repeat`).

## Spec, exemples & skill agent

- `docs/vasf-1-format.md` : section « VASF-2 extensions » (theme, layers, cycle,
  defs) + piège documenté (les `points` d'un path sont recentrés sur l'origine de
  la couche — le placer via le `x`/`y` de la couche).
- `docs/vasf-1-examples.json` : 3ᵉ exemple « Bonhomme qui hoche la tête »
  (vasf-2 : multi-couches + theme + defs + cycle).
- Skill agent `generer-animation-json` étendu à la v2 (validateur Python inclus :
  exemples 1/2/3 valides, recueil complet rejeté, erreurs v2 collectées).

## Analyse & tests

- `flutter analyze` : 0 problème ; **146 tests verts** — 10 nouveaux sur le format
  (version 2 acceptée / 3 rejetée, résolution et erreur d'alias, forme
  multi-couches importée en une forme, points de path par couche, round-trip
  export→import multi-couches, cycle de forme avec raccord propre, cycle ignoré
  sans keyframes / repeat invalide, ref avec surcharge + ref inconnue, cycle de
  squelette répété sur tous les os).

<!--
Ce fichier est utilisé tel quel comme description de chaque release GitHub.
Il est lu par le workflow .github/workflows/android.yml (body_path), puis complété
d'un pied de page (version · build · commit). Le mettre à jour AVANT chaque push.
-->
