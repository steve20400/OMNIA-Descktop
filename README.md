# OMNIA

**Lecteur personnel de médias, avec manipulation grâce au mobile.**

Lecteur universel desktop : vidéo, audio, PDF et texte dans une seule application.
Flutter + media_kit (libmpv), architecture « bus de commandes » prête pour la future télécommande mobile
([OMNIA-Mobile](https://github.com/steve20400/OMNIA-Mobile)).

> État : **Phase 3 — Confort de lecture** terminée.
> Phase 1 (fondations, thème, fenêtre, lecture audio/vidéo), Phase 2 (scan du dossier, panneau latéral,
> navigation, modes de fin de lecture, reprise de lecture) et Phase 3 (OSD, fichiers récents, menu
> contextuel, instance unique, aide `F1`, écran maintenu allumé) sont en place.
> Voir `DESIGN.md` pour le plan design.

## Plateformes

OMNIA s'installe sur **Windows** et **Linux (Ubuntu)** ; le code reste compatible macOS.
Un seul code source, aucune API spécifique à un système sans abstraction : les différences réelles
(codes d'erreur, position de fenêtre sous Wayland, bordures de redimensionnement, gestionnaire de
fichiers) sont isolées dans `lib/core/utils/` et `lib/core/services/`.

## Prérequis

Flutter stable ≥ 3.44 avec le support desktop activé.

### Windows

- Visual Studio 2022 avec le workload **« Développement Desktop en C++ »** (MSVC, CMake, Windows 10 SDK).
- **Mode développeur** activé, car les plugins Flutter utilisent des liens symboliques :

```bash
start ms-settings:developers
```

libmpv est embarqué par `media_kit_libs_video` : rien d'autre à installer.

### Linux (Ubuntu)

Compilation :

```bash
sudo apt install libmpv-dev mpv libgtk-3-dev clang cmake ninja-build pkg-config
flutter config --enable-linux-desktop
```

Exécution sur la machine cible (le bundle Flutter n'embarque pas libmpv) :

```bash
sudo apt install libmpv2 xdg-desktop-portal-gtk
```

### macOS

Xcode et CocoaPods. libmpv est embarqué.

## Compilation

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
    models/                 # PlaybackState, PlaylistState, MediaFile, HistoryEntry…
    services/               # PlaybackService, PlaylistService, FolderScanner, HistoryStore,
                            # SettingsStore, WindowService, SystemIntegration, SingleInstance, ScreenWake
    utils/                  # timecodes, tri naturel, codes d'erreur OS, session Wayland, arguments CLI
    providers.dart          # câblage Riverpod
  ui/
    app.dart                # MaterialApp, thème, i18n, mémorisation de la fenêtre
    screens/player_screen.dart
    widgets/                # barre de titre, contrôles, faisceau, scène, panneau, tuiles,
                            # OSD, menus (contextuel, récents), aide
    osd/                    # modèle et contrôleur de l'affichage à l'écran
    shortcuts/              # table de raccourcis par défaut + handler
    theme/                  # OmniaColors, OmniaTypography, OmniaMotion, OmniaMetrics
    panel_controller.dart   # état d'affichage du panneau (largeur, repli)
    recent_files.dart       # fichiers récents (avec existence vérifiée)
  l10n/                     # app_fr.arb (défaut), app_en.arb
assets/fonts/               # Instrument Sans, IBM Plex Mono (embarquées)
linux/                      # dev.omnia.omnia.desktop, dev.omnia.omnia.svg, CMake (mimalloc)
test/core/                  # tests unitaires du core
```

### Règle d'architecture

Toute action utilisateur devient une `PlayerCommand` publiée sur le `PlayerCommandBus`.
L'interface n'appelle **jamais** un contrôleur directement. Le `PlaybackService` écoute le bus,
route chaque commande (fenêtre, playlist, contrôleur de média actif, ou lui-même) et possède l'unique
`PlaybackState`, sérialisable en JSON, tout comme `PlaylistState`. Brancher un serveur WebSocket sur
le bus suffira pour la télécommande mobile.

## Playlist automatique du dossier

Ouvrir un fichier — par le bouton, un raccourci, un glisser-déposer, la ligne de commande ou le
gestionnaire de fichiers — déclenche le scan de son dossier parent. Tous les fichiers lisibles
apparaissent dans le panneau de gauche.

- Le scan tourne dans un isolate : l'interface ne gèle jamais, et la lecture démarre sans l'attendre.
- Tri naturel par défaut (`ep2` avant `ep10`), ou par date, taille, type ; ordre inversable.
- Recherche instantanée et filtre par type (tous / vidéo / audio / documents).
- Fichier en cours surligné, avec défilement automatique vers lui.
- Pastille « déjà lu » ou position mémorisée sur chaque ligne.
- Clic simple pour lire, clic droit pour le menu contextuel (lire, ouvrir l'emplacement, retirer).
- Panneau repliable (`Tab`) et redimensionnable à la souris ; largeur et état mémorisés.

## Confort de lecture

- **OSD** : chaque action au clavier (avance, volume, vitesse, muet, fichier suivant, mode de fin…)
  affiche un retour bref en haut de la scène, puis s'efface. Les actions à la souris n'en déclenchent
  qu'en plein écran, quand la barre de contrôles peut être masquée.
- **Fichiers récents** : menu sous le bouton « Ouvrir » de la barre de titre, et liste sur l'écran
  d'accueil. Un fichier est inscrit dès son ouverture ; un fichier déplacé reste listé, grisé.
- **Menu contextuel** (clic droit sur la scène) : lecture, fichier suivant/précédent, vitesse, fin de
  lecture, plein écran, premier plan, panneau, ouverture, emplacement du fichier. Sous-titres, pistes
  audio, image et capture s'y ajouteront en Phase 5.
- **Instance unique** : « Ouvrir avec → OMNIA » alors qu'OMNIA tourne déjà réutilise la fenêtre
  existante et remplace la lecture en cours. Voir « Compromis » pour le mécanisme.
- **Aide `F1`** : récapitulatif des raccourcis.
- **Veille** : l'écran reste allumé tant qu'une vidéo joue, et seulement là.

## Raccourcis

| Touche | Action |
|---|---|
| `Espace` | Lecture / pause |
| `←` / `→` | −5 s / +5 s (`Shift` : 30 s, `Ctrl` : 60 s) |
| `↑` / `↓` | Volume ±5 |
| `M` | Muet |
| `F` / double-clic | Plein écran (`Échap` pour sortir) |
| `N` / `P` | Fichier suivant / précédent |
| `+` / `-` / `=` | Vitesse + / − / 1× |
| `L` | Mode de fin de lecture (cycle) |
| `T` | Toujours au premier plan |
| `Tab` | Afficher / masquer le panneau |
| `Échap` | Quitter la recherche du panneau, fermer l'aide, quitter le plein écran |
| `Ctrl+O` / `Ctrl+Shift+O` | Ouvrir un fichier / un dossier |
| `F1` | Aide : récapitulatif des raccourcis |

Molette sur la vidéo : volume. Clic simple : lecture/pause. Clic droit : menu contextuel.

## Installation sur Ubuntu

```bash
flutter build linux --release
sudo mkdir -p /opt/omnia
sudo cp -r build/linux/x64/release/bundle/* /opt/omnia/
sudo ln -sf /opt/omnia/omnia /usr/local/bin/omnia

# Intégration au bureau. Le nom du fichier .desktop DOIT être l'identifiant
# d'application (dev.omnia.omnia), sinon GNOME ne peut pas relier la fenêtre
# à son icône sous Wayland.
mkdir -p ~/.local/share/applications ~/.local/share/icons/hicolor/scalable/apps
cp linux/dev.omnia.omnia.desktop ~/.local/share/applications/
cp linux/dev.omnia.omnia.svg     ~/.local/share/icons/hicolor/scalable/apps/
update-desktop-database ~/.local/share/applications
gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor
```

« Ouvrir avec → OMNIA » est ensuite proposé pour les formats audio et vidéo.
Les types PDF et texte seront ajoutés au fichier `.desktop` en même temps que leurs contrôleurs (Phase 4) :
les déclarer maintenant proposerait OMNIA pour des fichiers qu'il refuse encore d'ouvrir.

## Compromis documentés

- **Sourdine** : media_kit n'expose pas d'API « mute » ; OMNIA écrit la propriété native mpv `mute`, ce qui préserve le volume réglé. Sur une plateforme sans `NativePlayer`, seul l'état visuel change.
- **Durées dans le panneau** : sonder la durée de chaque fichier au scan coûterait une ouverture mpv par fichier. OMNIA n'affiche donc une durée que lorsqu'elle est déjà connue par l'historique, et se rabat sinon sur la taille du fichier.
- **Position de fenêtre sous Wayland** : le protocole interdit à une application de connaître ou d'imposer sa position. OMNIA n'y mémorise que la taille et laisse le compositeur placer la fenêtre.
- **Bordures de fenêtre sous Linux** : masquer la barre de titre retire toutes les décorations GTK. OMNIA redessine donc ses propres bords de redimensionnement (`DragToResizeArea`), inutiles sur Windows et macOS qui gardent leur cadre natif.
- **`N` en fin de liste** : la touche « fichier suivant » reboucle au premier fichier, alors que la lecture automatique en mode « suivant » s'arrête. Une action explicite ne doit pas être sans effet ; un enchaînement automatique ne doit pas tourner en rond sans qu'on l'ait demandé (mode « boucler le dossier » pour cela).
- **Vue audio** : pochette et fond dérivé prévus en Phase 5 ; pour l'instant, nom du morceau et symbole.
- **Instance unique** : le brief suggère un socket local ou D-Bus sous Linux. Ni l'un ni l'autre n'existe sous Windows, alors qu'OMNIA doit s'y installer aussi. La première instance écoute donc sur un port de la boucle locale (`127.0.0.1`, jamais exposé au réseau), noté avec un secret aléatoire dans `instance.json` du dossier de données ; une seconde instance lit ce fichier, transmet ses arguments et se termine. Un verrou périmé (instance tuée) est détecté par l'échec de connexion et réécrit.
- **Reprise de lecture** : la position mémorisée est appliquée par un seek juste après le démarrage ; on peut apercevoir la première image un instant. Le réglage « reprendre automatiquement / proposer / jamais » arrive avec les paramètres (Phase 6).
