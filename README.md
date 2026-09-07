# OMNIA

**Lecteur personnel de médias, avec manipulation grâce au mobile.**

Lecteur universel desktop : vidéo, audio, PDF et texte dans une seule application.
Flutter + media_kit (libmpv), architecture « bus de commandes » prête pour la future télécommande mobile
([OMNIA-Mobile](https://github.com/steve20400/OMNIA-Mobile)).

> État : **Phase 1 — Fondations** (architecture, thème, fenêtre, ouverture de fichiers, lecture audio/vidéo de base).
> Voir `DESIGN.md` pour le plan design.

## Plateformes

OMNIA s'installe sur **Windows** et **Linux (Ubuntu)** ; le code reste compatible macOS.
Un seul code source, aucune API spécifique à un système sans abstraction.

## Prérequis

Flutter stable ≥ 3.44 avec le support desktop activé (`flutter doctor` doit être vert pour la plateforme visée).

### Windows

- Visual Studio 2022 avec le workload **« Développement Desktop en C++ »** (MSVC, CMake, Windows 10 SDK).
- **Mode développeur** activé (les plugins Flutter utilisent des liens symboliques) :

```bash
start ms-settings:developers
```

libmpv est embarqué par `media_kit_libs_video` : rien d'autre à installer.

### Linux (Ubuntu)

```bash
sudo apt install libmpv-dev mpv libgtk-3-dev clang cmake ninja-build pkg-config
flutter config --enable-linux-desktop
```

### macOS

Xcode et CocoaPods. libmpv est embarqué.

## Installation et compilation

```bash
flutter pub get
```

Windows :

```bash
flutter run -d windows            # développement
flutter build windows --release   # exécutable dans build/windows/x64/runner/Release/
```

Linux :

```bash
flutter run -d linux              # développement
flutter build linux --release     # binaire dans build/linux/x64/release/bundle/
```

Ouvrir un fichier directement (« Ouvrir avec ») :

```bash
flutter run -d windows -- "C:\Videos\episode.mkv"
./build/linux/x64/release/bundle/omnia /chemin/vers/episode.mkv
```

## Qualité

```bash
flutter analyze   # doit être vierge
flutter test      # tests unitaires du core
```

## Structure du projet

```
lib/
  main.dart                 # initialisation (media_kit, Hive, fenêtre), ProviderScope
  core/                     # logique pure, sans widget
    commands/               # PlayerCommand (sealed, JSON) + PlayerCommandBus
    controllers/            # MediaController, AvController (mpv), MediaRouter
    models/                 # PlaybackState, MediaFile, MediaType, modes, statuts
    services/               # PlaybackService, WindowService, SettingsStore (Hive)
    utils/                  # formatage des timecodes
    providers.dart          # câblage Riverpod
  ui/
    app.dart                # MaterialApp, thème, i18n, mémorisation de la fenêtre
    screens/player_screen.dart
    widgets/                # barre de titre, contrôles, faisceau, scène, boutons
    shortcuts/              # table de raccourcis par défaut + handler
    theme/                  # OmniaColors, OmniaTypography, OmniaMotion, OmniaMetrics
    file_dialogs.dart       # dialogues natifs → commandes sur le bus
  l10n/                     # app_fr.arb (défaut), app_en.arb
assets/fonts/               # Instrument Sans, IBM Plex Mono (embarquées)
linux/omnia.desktop         # intégration bureau + associations MIME
test/core/                  # tests unitaires du core
```

### Règle d'architecture

Toute action utilisateur devient une `PlayerCommand` publiée sur le `PlayerCommandBus`.
L'interface n'appelle **jamais** un contrôleur directement. Le `PlaybackService` écoute le bus,
route chaque commande (fenêtre, contrôleur de média actif, ou lui-même) et possède l'unique
`PlaybackState`, lui aussi sérialisable en JSON. Brancher un serveur WebSocket sur le bus
suffira pour la télécommande mobile.

## Raccourcis (Phase 1)

| Touche | Action |
|---|---|
| `Espace` | Lecture / pause |
| `←` / `→` | −5 s / +5 s (`Shift` : 30 s, `Ctrl` : 60 s) |
| `↑` / `↓` | Volume ±5 |
| `M` | Muet |
| `F` / double-clic | Plein écran (`Échap` pour sortir) |
| `+` / `-` / `=` | Vitesse + / − / 1× |
| `T` | Toujours au premier plan |
| `L` | Mode de fin de lecture (cycle) |
| `Ctrl+O` / `Ctrl+Shift+O` | Ouvrir un fichier / un dossier |

Molette sur la vidéo : volume. Clic simple : lecture/pause.

## Installation du fichier `.desktop` (Ubuntu)

```bash
flutter build linux --release
sudo mkdir -p /opt/omnia
sudo cp -r build/linux/x64/release/bundle/* /opt/omnia/
sudo ln -sf /opt/omnia/omnia /usr/local/bin/omnia
cp linux/omnia.desktop ~/.local/share/applications/
update-desktop-database ~/.local/share/applications
```

Ensuite, « Ouvrir avec → OMNIA » est proposé par le gestionnaire de fichiers pour tous les types listés dans `MimeType`.
(Une icône `omnia.png` sera ajoutée en Phase 6 dans `~/.local/share/icons/hicolor/`.)

## Compromis documentés

- **Sourdine** : mpv ne propose pas d'API « mute » dans media_kit ; OMNIA utilise la propriété native `mute`, ce qui préserve le volume réglé. Sur une plateforme sans `NativePlayer`, seul l'état visuel change.
- **Ouverture d'un dossier** (Phase 1) : lit le premier fichier lisible par ordre alphabétique. Le scan complet, le tri naturel et le panneau arrivent en Phase 2.
- **Vue audio** (Phase 1) : nom du morceau et symbole ; pochette et fond dérivé en Phase 5.
