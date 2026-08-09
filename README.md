# Lafee Damage Type Tracker

Lafee Damage Type Tracker affiche, en temps réel, la part de dégâts physiques et magiques subis par votre personnage sur une courte fenêtre glissante.

La barre est légère, configurable par personnage et peut rester libre ou s’aligner automatiquement avec certaines interfaces populaires.

## Fonctionnalités

- Suivi des dégâts subis physiques et magiques.
- Fenêtre d’analyse réglable de 2 à 10 secondes.
- Barre affichée avec transparence réduite hors combat.
- Largeur, hauteur et position libres configurables.
- Bouton de minicarte déplaçable.
- Profils enregistrés séparément pour chaque personnage, avec copie de configuration.
- Deux styles visuels : **Carré** (par défaut) et **Classique**.
- Intégration optionnelle avec BetterCooldownManager et ElvUI.
- Interface traduite en français, anglais, allemand, espagnol, chinois simplifié et chinois traditionnel selon la langue du client WoW.

## Ancrage de la barre

Trois modes sont disponibles dans les options :

- **Libre** : positionnement manuel habituel.
- **BetterCooldownManager** : ancrage à une barre BCDM, avec choix de plusieurs barres connues ou saisie manuelle d’une frame BCDM.
- **ElvUI** : ancrage à la barre de puissance du joueur lorsqu’elle est affichée. Si cette barre est absente ou masquée, Lafee Damage Type Tracker se place au centre de l’écran.

Pour les intégrations BCDM et ElvUI, vous pouvez choisir un placement au-dessus ou en dessous, l’espacement vertical et l’option **Même largeur que la barre**. En mode BetterCooldownManager, des décalages X/Y supplémentaires sont disponibles.

BetterCooldownManager et ElvUI sont entièrement facultatifs : l’addon fonctionne normalement sans eux.

## Installation

1. Téléchargez puis décompressez l’archive.
2. Placez le dossier `Lafee_damage_tracker` dans :
   `World of Warcraft/_retail_/Interface/AddOns/`
3. Lancez le jeu ou utilisez `/reload`.

## Utilisation

Utilisez le bouton de la minicarte ou la commande suivante :

| Commande | Action |
| --- | --- |
| `/ldt` | Affiche ou masque la barre. |
| `/ldt config` | Ouvre les options. |
| `/ldt clear` | Réinitialise les dégâts actuellement suivis. |
| `/ldt reset` | Réinitialise la position libre de la barre. |

## Compatibilité

- World of Warcraft Retail.
- BetterCooldownManager *(optionnel)*.
- ElvUI *(optionnel)*.

## Notes

- Les réglages sont sauvegardés par personnage dans `LafeeDamageTrackerDB`.
- Les changements de mode d’intégration demandent un `/reload` pour finaliser proprement l’interface.
- L’addon ne modifie aucun fichier d’ElvUI ou de BetterCooldownManager.
