# OMNIA — Plan design

> Concept : **salle de projection personnelle**. L'interface est un rideau : elle se retire
> quand le contenu joue, et quand on la rappelle, elle est belle. Une seule source de lumière
> dans la pièce : le projecteur. Tout ce qui brille dans l'UI brille de cette lumière-là.

## 1. Palette (thème sombre, par défaut)

| Nom | Hex | Rôle |
|---|---|---|
| **Velours** | `#120F14` | Fond principal. Noir profond teinté prune — le velours des fauteuils, pas un `#111` neutre. |
| **Rideau** | `#1C1720` | Surfaces surélevées : panneau latéral, barre de titre, overlays (avec translucidité + flou). |
| **Couture** | `#2E2734` | Bordures, séparateurs, pistes de curseurs au repos. |
| **Projecteur** | `#F2B441` | Accent unique. Lumière ambre du projecteur : progression, focus, élément actif. |
| **Braise** | `#C9822B` | Accent pressé / secondaire, texte sur fond ambre trop clair. |
| **Écran** | `#F3EFE6` | Texte principal. Blanc chaud d'un écran de cinéma, jamais `#FFFFFF`. |
| **Poussière** | `#9C9199` | Texte secondaire, icônes inactives — la poussière dans le faisceau. |
| **Alerte** | `#E0573C` | Erreurs uniquement. |

Règles :
- Une seule couleur d'accent. Le bleu/violet SaaS est banni.
- Les surfaces flottantes sont `Rideau` à 78 % d'opacité + flou 18 px, coin 14 px, ombre `#000` 35 % / flou 24 px.
- Les états de survol éclaircissent de 6 % (jamais de changement de teinte).

## 2. Thème clair (secondaire)

| Nom | Hex | Rôle |
|---|---|---|
| Papier | `#F6F1EA` | Fond |
| Lin | `#FFFDF9` | Surfaces |
| Fil | `#E3DBD1` | Bordures |
| Projecteur | `#C98A17` | Accent (assombri pour le contraste) |
| Encre | `#1E181F` | Texte principal |
| Sépia | `#6E6469` | Texte secondaire |

## 3. Typographie

| Famille | Rôle | Pourquoi |
|---|---|---|
| **Instrument Sans** (variable, embarquée) | Toute l'interface : titres, listes, boutons, paramètres | Géométrique sans être froide, chiffres bien dessinés, plus rare que Inter/Roboto. |
| **IBM Plex Mono** (Regular + Medium, embarquée) | Timecodes, compteurs de pages, vitesse, volume, raccourcis | Chiffres à chasse fixe : l'alignement `00:00:00` ne bouge jamais d'un pixel. |

Échelle (px) : 11 (légende), 12.5 (secondaire), 14 (corps), 16 (titre de section), 22 (titre de vue), 32 (titre audio).
Timecodes : 12.5 Plex Mono Medium, `letterSpacing: 0.4`.

## 4. Layout en une phrase

Une seule scène plein cadre pour le contenu ; le panneau du dossier à gauche et les contrôles en bas
sont des rideaux qui glissent hors du cadre et n'y reviennent qu'à la demande.

## 5. Signature visuelle — le faisceau

**La barre de progression est un faisceau de projecteur.**
- Au repos : trait de 2 px, `Couture` pour le restant, `Projecteur` pour l'écoulé.
- L'écoulé porte un halo (ombre `Projecteur` 55 % / flou 10 px) : la lumière « chauffe » le temps déjà vu.
- La tête de lecture est une lampe : disque 10 px `Écran` avec halo `Projecteur` 12 px, qui s'allume au survol.
- Au survol : la piste passe à 6 px en 180 ms (`easeOutCubic`), le timecode survolé s'affiche dans une bulle mono.
- Le même halo est réutilisé une seule autre fois : l'OSD (retour clavier) est une pastille éclairée par ce faisceau.

Nulle part ailleurs de lueur, dégradé ou animation décorative. Toute l'audace est dépensée ici.

## 6. Motion

| Situation | Durée | Courbe |
|---|---|---|
| Survol (couleur, épaisseur) | 150 ms | `easeOut` |
| Apparition/disparition des contrôles, OSD | 200 ms | `easeOutCubic` / `easeIn` |
| Rétraction du panneau latéral | 240 ms | `easeInOutCubic` |
| Transition entre types de média | 250 ms | fondu + léger scale 0.985 → 1 |

Le motion répond toujours à une action. Aucune boucle décorative.

## 7. Le hall — l'accueil (refonte de novembre 2026)

> Référence demandée : l'écran d'accueil d'une console (PlayStation, Switch) et des
> façades d'émulateurs (Playnite plein écran, LaunchBox Big Box, ES-DE). Une page qu'on
> laisse ouverte parce qu'elle est belle à l'arrêt.

Dans un cinéma, le hall affiche ce qui passe. L'accueil d'OMNIA aussi :
- **La bande d'affiches** : les médias ouverts dernièrement, en affiches 16:10 (image du
  film, pochette, première page du PDF, la photo). On la parcourt à la souris ou au
  clavier, comme à la manette : ← → pour bouger, Entrée pour ouvrir. ↑ ↓ restent le volume.
- **L'affiche sélectionnée est éclairée par le projecteur** : elle grandit (0,9 → 1), prend
  un bord `Projecteur` de 2 px et un halo `Projecteur` 38 % / flou 26 px. C'est le seul
  autre endroit, avec le faisceau, où la lumière du projecteur se pose.
- **Le fond suit la sélection** : l'affiche choisie, floutée (σ 40), à 60 % sur le velours,
  avec deux voiles de lisibilité (bas → haut, gauche → droite). Ces voiles ne décorent
  pas : ils gardent le texte lisible sur n'importe quelle image. Réglable : affiche,
  image personnelle, ou velours uni.
- **La séance** : au-dessus de la bande, le titre (32, sans les points des noms de
  fichiers), le type en `Projecteur`, où l'on en est en Plex Mono (« Reprise à 12:05 sur
  40:00 »), puis « Reprendre » et « Afficher dans le dossier ».
- **Le faisceau au pied de chaque affiche** : 3 px, la part déjà vue en `Projecteur` —
  la même lumière que la barre de progression.
- **En haut** : les rayons (Tout, Vidéos, Musique, Documents, Images), soulignés par un
  trait de faisceau quand ils sont choisis ; l'heure en Plex Mono à droite, la date dessous.
- **En bas** : Ouvrir un fichier, Ouvrir un dossier, et la bannière mobile quand il y a
  la place.

Mise en page : marges latérales de 32 px (16 px sous 560 px de large), 24 px entre les
blocs. Affiches de 132 à 248 px de large selon la fenêtre. Tout texte qui peut s'allonger
tient sur une ou deux lignes, coupé net. Sous 240 px de haut, le hall défile au lieu de
déborder.

## 8. Auto-critique

- *Fond quasi noir + ambre* : classique « cinéma », mais assumé parce que c'est le concept. La prune (pas le bleu-nuit)
  et le blanc chaud évitent le rendu « terminal ».
- *Instrument Sans* plutôt qu'Inter/Manrope : elle a une personnalité (le `a` et le `g`) sans nuire à la lisibilité.
- *Signature* : un seul point lumineux. Si un futur écran veut un deuxième effet, il le refuse.
