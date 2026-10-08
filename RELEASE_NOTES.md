# Keyform Studio 0.34.0

## Création et format du projet

- **Nouveau projet** crée un canvas vierge avec les réglages par défaut, lui attribue un nom daté à la microseconde et ouvre directement le Studio, sans boîte de dialogue.
- Nouveau menu Studio **Canvas** avec huit formats radio : 9:16, 4:5, 3:4, 1:1, 4:3, 3:2, 16:9 et 21:9. Le changement de ratio ajuste les dimensions du projet, est sauvegardé et peut être annulé.
- Le compteur et le texte d’aide du menu **Éléments** sont retirés ; les nouveaux rectangles ont des coins carrés, sans modifier l’arrondi des formes existantes ni des VASF historiques.

### Vérifications

- `flutter analyze` sans problème.
- Suite complète des tests Flutter : 293 tests passés.
