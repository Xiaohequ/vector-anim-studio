# Vector Anim Studio 0.13.0

## Nouveautés

- **vasf-2 Groupe 2 — moteur léger** : quatre extensions du format d'échange,
  toutes développées à l'import (un fichier `version: 1` reste importable tel
  quel, le moteur est inchangé) :
  - **`scaleX` / `scaleY` par keyframe** : squash & stretch non uniformes
    animables (« Échelle X/Y » dans la sheet de propriétés). L'échelle
    effective = `scale` × facteur d'axe (composition au rendu) — la keyframe
    porte le FACTEUR brut : une keyframe à 1 REMPLACE le facteur de base, elle
    ne le restaure pas (finir le motif sur la valeur de base pour un bouclage
    propre). Les gestes pinch restent multiplicatifs sur la base.
  - **Pivot de rotation** : offset `[dx, dy]` en unités de forme depuis le
    centre, où rotation ET échelle tournent (portes, balances — sinon il
    fallait passer par un os). STATIQUE (non animable) ; gond ancré à sa
    position visuelle `centre + S·pivot` — sous une échelle non uniforme, le
    gond reste collé au bord visuel de la forme. Chaîne painter =
    translate(x,y) · translate(S·pivot) · rotate · scale(eff) · translate(−pivot).
    Lignes de réglage pivot dans la sheet de propriétés.
  - **Easing cubic-bezier** : `customBezier` sur les keyframes de forme ET
    d'os, chaîne CSS `cubic-bezier(x1, y1, x2, y2)` (x1/x2 bornés [0, 1],
    dichotomie 60 itérations ; identité linéaire = (1/3, 1/3, 2/3, 2/3) —
    PAS (0,0,1,1) qui est un smoothstep). Option « Personnalisé (Bézier) »
    dans les deux dropdowns d'easing ; édition des 4 paramètres
    import-seulement.
  - **Liaison de couche exposée dans `bind`** : clé `"Forme/Couche"` → os
    (la structure `BoneBinding.layerId` existait, le format l'ignorait).
    Une forme avec liaison de couche est EXPORTÉE en `layers[]` même à une
    seule couche (le nom de couche doit survivre au round-trip) ; l'import
    exige une couche nommée existante, sinon erreur collectée.
- Export `version: 2` dès qu'une extension G1 **ou** G2 est présente
  (multi-couches, liaison de couche, scaleX/Y ≠ 1, pivot ≠ 0, customBezier).

## Spec, exemples & skill agent

- `docs/vasf-1-format.md` : nouvelles sections « Axis scale », « Pivot »,
  « Custom easing », « Layer bindings » ; tableau des champs et keyframes mis
  à jour ; limites réécrites (la liaison de couche n'est plus ignorée).
- `docs/vasf-2-example.json` (G1) désormais commité + pointeur dans la spec ;
  `docs/vasf-2-g2-example.json` (G2) : balle squash+stretch en cubic-bezier,
  porte tournant sur son pivot, lampe dont la couche est liée à un os en cycle.
- Skill agent `generer-animation-json` + validateur Python étendus au Groupe 2
  (facteurs d'axe au niveau base et keyframes, pivot, easing cubic-bezier —
  x1/x2 hors bornes, liaison `Forme/Couche` — couche/forme/os inconnus) ;
  références du skill à jour (spec + 2 exemples v2).

## Analyse & tests

- `flutter analyze` : 0 problème ; **153 tests verts** — 7 nouveaux sur le
  Groupe 2 (facteurs d'axe base + keyframes avec portage, pivot de forme,
  easing cubic-bezier valide/hors bornes, liaison de couche round-trip,
  couche inconnue en erreur).

<!--
Ce fichier est utilisé tel quel comme description de chaque release GitHub.
Il est lu par le workflow .github/workflows/android.yml (body_path), puis complété
d'un pied de page (version · build · commit). Le mettre à jour AVANT chaque push.
-->
