# Keyform Studio 0.28.1

## Correctifs pour les groupes squelette

- Lorsqu'un élément de groupe squelette est resélectionné après un autre
  élément, son overlay affiche à nouveau toute la chaîne d'os qui lui est liée.
  Les os ajoutés au groupe redeviennent visibles et manipulables dans le preview.
- Le libellé du segment de groupe sur la timeline n'inclut plus l'icône d'os ;
  la couleur orange distincte reste conservée.

### Vérifications

- Test de régression : changer de sélection puis resélectionner le groupe
  réaffiche sa chaîne d'os dans l'overlay et permet de sélectionner un os.
- La CI doit confirmer l'analyse, la suite complète et le build APK avant
  publication.
