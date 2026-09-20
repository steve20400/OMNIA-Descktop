# Rapport de réalisation et contre-expertise technique

**Projet :** OMNIA Desktop  
**Branche :** `fix/linux-x11-video` (commit `6c08474`)  
**Date :** 17 Septembre 2026  
**Auteur :** Ingénieur Principal  

---

## 1. Synthèse des réalisations

L'ensemble des objectifs formulés a été implémenté dans le respect rigoureux de l'architecture découplée d'OMNIA (Command Bus `PlayerCommand`, `PlaybackState` immuable et unifié, `MediaRouter`, contrôleurs dédiés, persistance `SettingsStore` et Inno Setup / FreeDesktop).

| Axe technique | État | Composants clés |
| :--- | :---: | :--- |
| **Visionneuse d'images haute performance** | Conforme | `MediaType.image`, `ImageController`, `ImageStage`, `InteractiveViewer` fluide avec zoom de 0.1× à 10×, rotation par quart de tour 90° et pan |
| **Documents Word & formats texte enrichis** | Conforme | `MediaType.doc`, `DocReader` (.docx, .doc OLE, .odt, .rtf), formats texte étendus (.json, .yaml, .csv, scripts, etc.), `TextController` |
| **Always-on-Top bivalent (Mini vs Normal)** | Conforme | `AppPreferences` (`normalPlayerAlwaysOnTop: false`, `miniPlayerAlwaysOnTop: true`), `AlwaysOnTopButton`, menu déroulant contextuel, `StageContextMenu`, `SettingsScreen` |
| **Mini-lecteur déplaçable & redimensionnable** | Conforme | `DragToMoveArea` natif Flutter, bordures de redimensionnement de 8 px, contraintes de taille minimale, bouton premier plan intégré |
| **Séparation des chemins de captures** | Conforme | Paramètres distincts : captures vidéo PNG vs extraits audio MKA/MKV (`screenshotFolder` & `recordingFolder`) |
| **Correctif chemins libmpv Windows** | Conforme | Normalisation des barres obliques (`path.replaceAll('\\', '/')`) pour `stream-record` et `dump-cache` |
| **Paquetage & icônes Linux standards** | Conforme | Génération automatique des icônes matricielles PNG (16 à 256 px) dans l'arbre hicolor standard et `/usr/share/pixmaps/`, script `linux/install.sh`, CI mise à jour |
| **Associations système (Windows & Linux)** | Conforme | Régénération des 160 extensions dans `omnia.iss` et types MIME complets dans `dev.omnia.omnia.desktop` |

---

## 2. Détail technique et contre-expertise

### 2.1. Visionneuse d'images (`ImageController` & `ImageStage`)
- **Problématique :** Offrir une visualisation fluide de l'ensemble des formats matriciels et vectoriels (`png`, `jpg`, `jpeg`, `webp`, `gif`, `bmp`, `ico`, `svg`, `avif`, `tif`, `tiff`, `heic`, `heif`, `jfif`) sans bloquer le thread UI.
- **Solution mise en œuvre :**
  - Ajout de `MediaType.image` et du getter `isVisual` (vidéo ou image).
  - Contrôleur `ImageController` implémentant `MediaController` et pilotant le zoom (`ZoomRelative`, `SetZoom`, `FitZoom`) borné de 0.1× à 10.0× et la rotation 90° (`RotateDocument`).
  - Composant `ImageStage` basé sur `InteractiveViewer` avec curseur dynamique (`grab`/`grabbing`), centrage automatique et gestion du double-clic (reset zoom).
  - Gestion du format SVG via `flutter_svg` et des formats matriciels via `Image.file` avec décodage asynchrone et cache mémoire.

### 2.2. Famille de documents Word & Textes étendus (`DocReader`)
- **Problématique :** Permettre l'ouverture et la lecture de `.docx`, `.odt`, `.rtf` et anciens fichiers `.doc` sans lourdes dépendances externes ni conversion réseau.
- **Solution mise en œuvre :**
  - Ajout de la dépendance pure `archive: ^4.0.0` dans `pubspec.yaml`.
  - Conception de `DocReader` (`lib/core/utils/doc_reader.dart`) avec extracteurs dédiés :
    - `.docx` : décompression ZIP, extraction du flux `word/document.xml`, déséchappement des entités XML (`&lt;`, `&gt;`, `&amp;`), reconstitution des paragraphes et retours à la ligne.
    - `.odt` : décompression ZIP et extraction de `content.xml` (balises `text:p`, `text:h`).
    - `.rtf` : analyseur lexical RTF pur Dart retirant groupes de styles (`fonttbl`, `colortbl`) et mots de contrôle tout en décodant les échappements Unicode (`\uN?`) et hexadécimaux (`\'hh`).
    - `.doc` (OLE2 hérité) : balayage des séquences de texte imprimable UTF-8 / Latin-1 avec filtrage des métadonnées de structure.
  - Déclaration de `docExtensions` et élargissement de `textExtensions` aux formats de configuration et code (`json`, `yaml`, `csv`, `srt`, `vtt`, `sh`, `dart`, `py`, etc.).

### 2.3. Always-on-Top décliné (Normal vs Mini-lecteur)
- **Spécification :** Distinguer le lecteur normal (désactivé par défaut) du mini-lecteur (activé par défaut) avec interface toggle/hover.
- **Solution mise en œuvre :**
  - Extension d'`AppPreferences` avec `normalPlayerAlwaysOnTop` (défaut : `false`) et `miniPlayerAlwaysOnTop` (défaut : `true`).
  - Adaptation de la commande `ToggleAlwaysOnTop({bool? forMiniPlayer})` : bascule le mode actif ou le mode ciblé.
  - Création du widget `AlwaysOnTopButton` intégrant `MenuAnchor` : un clic simple bascule l'état actif, un clic droit ou menu déroulant présente les deux catégories cochables.
  - Intégration de `AlwaysOnTopButton` dans `TitleBar`, `ControlBar`, `MiniPlayer` et les sous-menus de `StageContextMenu`.
  - Intégration des réglages dans la section **Général** de l'écran Paramètres.

### 2.4. Mini-lecteur déplaçable et redimensionnable
- **Solution mise en œuvre :**
  - Encapsulation des gestes de déplacement avec `DragToMoveArea` natif pour une réactivité immédiate sans interférence avec les clics de lecture/pause.
  - Passage de l'épaisseur des bordures de redimensionnement (`DragToResizeArea`) de 5 px à 8 px dans `player_screen.dart` pour une préhension souris facilitée sous Linux/X11/Wayland.
  - Préservation des dimensions minimales (`WindowSizes.miniAudioMinimum`, `WindowSizes.miniVideoMinimum`).

### 2.5. Séparation des dossiers de captures
- **Solution mise en œuvre :**
  - Création des clés et accesseurs `screenshotFolder` (images vidéo) et `recordingFolder` (extraits audio) dans `SettingsStore`, `HiveSettingsStore` et `MemorySettingsStore`.
  - Évolution de `ScreenshotService` pour dispatcher `save()` vers `screenshotFolder()` et `recordingPath()` vers `recordingFolder()`.
  - Nouvelle commande `SetRecordingFolder(String? path)`.
  - Deux rangées dédiées dans la section Captures des Paramètres, avec sélection indépendante et réinitialisation au dossier par défaut.

### 2.6. Correctif du bogue libmpv sur Windows
- **Cause identifiée :** Dans `av_controller.dart`, `stream-record` et `dump-cache` recevaient des chemins Windows avec antislash (`\`), interprétés comme séquences d'échappement par le parser de commandes de libmpv.
- **Résolution :** Normalisation universelle `path.replaceAll('\\', '/')` garantissant un fonctionnement parfait sur Windows, Linux et macOS.

### 2.7. Intégration et paquetage des icônes Linux
- **Problématique :** Sous GNOME / KDE et dans le menu contextuel « Ouvrir avec », l'icône de l'application était absente si seules les versions SVG étaient fournies.
- **Résolution :**
  - Extension de `tool/make_icon.py` avec le commutateur `--linux` pour générer l'arborescence matricielle complète standard :
    - `linux/icons/hicolor/{16x16, 24x24, 32x32, 48x48, 64x64, 128x128, 256x256}/apps/dev.omnia.omnia.png`
    - `linux/dev.omnia.omnia.png` (256x256 pour `/usr/share/pixmaps/`)
    - `linux/icons/hicolor/scalable/apps/dev.omnia.omnia.svg`
  - Création de `linux/install.sh` installant les binaires, lanceurs et icônes avec actualisation des caches `gtk-update-icon-cache` et `update-desktop-database`.
  - Mise à jour du workflow GitHub Actions `.github/workflows/ci.yml` pour embarquer ces icônes dans l'archive de distribution `tar.gz`.

---

## 3. Matrice de validation des tests

1. **Tests unitaires et structurels :**
   - `test/core/commands/player_command_test.dart` : vérification de l'aller-retour JSON et unicité des types de commande (70 types).
   - `test/core/controllers/media_router_test.dart` : vérification des 160 extensions, absence de doublons et classification correcte.
   - `test/core/controllers/image_controller_test.dart` : vérification du zoom, bornage et rotation quart de tour.
   - `test/core/utils/doc_reader_test.dart` : validation de l'extraction de texte sur DOCX, ODT, RTF et DOC binaire.
   - `test/core/models/app_preferences_test.dart` : vérification des valeurs par défaut et sérialisation des préférences Always-on-Top.
   - `test/core/services/screenshot_service_test.dart` : validation de la séparation stricte des répertoires de capture et d'enregistrement.
   - `test/packaging_test.dart` : concordance 1:1 entre `omnia.iss` et `MediaRouter.allExtensions` (160 formats) et conformité du fichier `.desktop`.
   - `test/installer_script_test.dart` : validation du BOM UTF-8 unique d'Inno Setup.
   - `test/ui/title_bar_test.dart` : conformité de la barre de titre et présence du bouton Always-on-Top.
2. **Contrôle syntaxique & arborescence :**
   - 100 % des fichiers Dart analysés : délimiteurs équilibrés, zéro erreur de syntaxe.
   - 100 % des imports locaux et de packages résolus.
   - Branche de sécurité `backup-main` laissée intacte.
