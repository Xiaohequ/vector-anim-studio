# Vector Anim Studio 0.10.0

## Nouveautés

- **Ordre de dessin par os (z).** Chaque os porte un réglage « Ordre (z) » dans ⚙ Propriétés de l'os (slider −10…+10). Les pièces du projet squelette sont dessinées triées par le z de leur os porteur — une pièce à z négatif passe DERRIÈRE les autres, indispensable pour un bras derrière le torse. z égal → ordre de la timeline ; les couches liées individuellement suivent le z de LEUR os.
- **Opacité / étirement / écrasement par keyframe d'os.** ⚙ Propriétés de l'os expose trois sliders animables : Opacité (0–1), Étirement le long de l'os (0,2–3), Écrasement perpendiculaire (0,2–3). Ils s'échantillonnent à la timeline comme l'angle : tenus hors plage, interpolés selon l'easing de la keyframe, neutres (1) sans piste. L'opacité multiplie la pose des pièces portées ; l'étirement/écrasement déforme l'os ET déplace l'articulation des os enfants (les offsets relatifs suivent le stretch du parent).
- **IK 2 os.** Dans ⚙ Propriétés de l'os, un interrupteur « IK 2 os » s'active sur un os portant EXACTEMENT un enfant (sinon il reste grisé). Le glisser de l'extrémité de l'enfant (effecteur, marqueur vert en losange) résout la chaîne : le bout suit le doigt, le coude plie. Os animé → keyframe au curseur (auto-key) ; os non animé → pose du rig avec emport des pièces liées. « Inverser le coude » bascule le côté du pli. Cible hors de portée : la chaîne se tend au maximum vers elle.

## Analyse & tests

- `flutter analyze` : 0 problème ; solveur IK vérifié numériquement (L1=L2=50, cible (60,0) → angles ±0,9273 rad, bout de chaîne sur la cible, miroir bend −1), samplers/hold/interp, stretch FK, z de forme et de couche, fusion upsertKeyframe (l'angle n'écrase pas l'opacité), round-trip JSON.

<!--
Ce fichier est utilisé tel quel comme description de chaque release GitHub.
Il est lu par le workflow .github/workflows/android.yml (body_path), puis complété
d'un pied de page (version · build · commit). Le mettre à jour AVANT chaque push.
-->
