# Vector Anim Studio 0.25.0

## Nouvelle icône d'application « TRAIL »

- Un cadre net accompagné de ses échos de mouvement et d'un point coloré :
  l'animation par couches, résumée en un seul signe.
- Icône générée par script (`tmp/generer_icones.py`) : tailles, dégradé de fond et
  zone sûre calculés pour coller aux masques système.
- **Android** : mipmaps mdpi → xxxhdpi **plus icône adaptative** (`anydpi-v26`,
  avant-plan transparent + fond `#0B2129`) — rendu correct en cercle comme en
  carré arrondi sur les launchers récents.
- **iOS** : catalogue `AppIcon.appiconset` régénéré, de 20 pt au 1024 pt demandé
  par l'App Store (fond plein cadre, sans transparence, sans texte).
- Lisibilité vérifiée jusqu'à 32 px.

### Vérifications

- CI sur la PR #1 : analyse statique, **266/266 tests** et
  `flutter build apk --release` avec les nouvelles ressources — tous verts.
- Validation de l'icône sur appareil (et rendu Xcode) à confirmer.
