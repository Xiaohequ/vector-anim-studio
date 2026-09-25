# Vector Anim Studio 0.9.6

## Nouveautés

- **Liaison au niveau couche.** Une couche précise d'une pièce peut maintenant être liée à son propre os (au lieu d'une pièce entière par os). Dans ⚙ Propriétés de la forme (projet squelette), une section « Couches liées au rig » liste chaque couche avec son os porteur et une action Lier…/Délier. La couche liée suit SON os, indépendamment des couches voisines ; la liaison de couche prend le pas sur la liaison de la forme entière (qui reste disponible). Rigguer un personnage dessiné en une seule forme devient possible : une couche par membre, un os par couche.
- **Le déplacement d'ancrage emporte les couches liées** : tourner ou déplacer un os transporte les couches liées (et les pièces entières) comme avant — le rendu applique la transformée de l'os porteur par couche.
- **Duplication fidèle** : dupliquer une pièce emporte ses liaisons (forme entière et couches, ids remappés).
- **Import squelette → projet vectoriel, avec badge de type** : « Formes ▸ Insérer une animation… » liste les projets vectoriels ET squelettes ; le sous-titre affiche le type (vectorielle / squelette), la durée et le nombre de pièces. Le personnage riggé devient une instance animable (position/échelle/keyframes de forme) dans une scène — le rig du sous-projet est échantillonné à son temps de boucle, 1 niveau d'imbrication maximum.

## Analyse & tests

- `flutter analyze` : 0 problème ; **112 tests verts** (liaison de couche : remplacement/purge, round-trip JSON avec compat ascendante, emport de couche lors de la pose du rig, duplication remappée, instance de squelette dans un vectoriel).

<!--
Ce fichier est utilisé tel quel comme description de chaque release GitHub.
Il est lu par le workflow .github/workflows/android.yml (body_path), puis complété
d'un pied de page (version · build · commit). Le mettre à jour AVANT chaque push.
-->
