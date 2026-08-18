# Lafee Damage Type Tracker

Lafee Damage Type Tracker affiche, en temps réel, la part de dégâts physiques et magiques subis par votre personnage sur une courte fenêtre glissante.

La barre est légère, configurable par personnage et peut rester libre ou s’aligner sur toute frame WoW accessible.

## Fonctionnalités

- Suivi des dégâts subis physiques et magiques.
- Fenêtre d’analyse réglable de 2 à 10 secondes.
- Barre affichée avec transparence réduite hors combat.
- Largeur, hauteur et position libres configurables.
- Ancre Lafée stable, utilisable par d’autres addons via une API publique versionnée.
- Bouton de minicarte déplaçable.
- Profils enregistrés séparément pour chaque personnage, avec copie de configuration.
- Deux styles visuels : **Carré** (par défaut) et **Classique**.
- Interface traduite en français, anglais, allemand, espagnol, chinois simplifié et chinois traditionnel selon la langue du client WoW.

## Ancrage de la barre

Deux modes sont disponibles dans la page **Positionnement** :

- **Libre** : positionnement manuel habituel.
- **Ancrée** : liaison de l’ancre Lafée à `UIParent`, à une frame Blizzard connue ou à un nom de frame saisi manuellement.

Les points, points relatifs et décalages sont configurables. L’option d’héritage de largeur utilise les contraintes natives de WoW : la barre suit automatiquement les changements de largeur de la frame cible, sans recalcul à chaque image.

Le sélecteur défilant détecte aussi dynamiquement les frames globales chargées de BetterCooldownManager (`BCDM_*`). Pour ElvUI, il limite volontairement la liste au cadre joueur, à ses barres directes de vie, ressource, classe et incantation, ainsi qu’aux barres d’action `ElvUI_Bar*`. Les cadres Target, Party, Raid, Boss et Arena sont exclus. Cette découverte ne crée aucune dépendance ni intégration côté BCM ou ElvUI.

Les auteurs d’addons peuvent récupérer l’ancre `Main` ou la lier temporairement à leur propre frame. Voir [docs/API.md](docs/API.md).

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

## Notes

- Les réglages sont sauvegardés par personnage dans `LafeeDamageTrackerDB`.
- Les anciennes positions et anciens profils sont migrés automatiquement.
