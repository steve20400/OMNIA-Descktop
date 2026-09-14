# OMNIA

**Lecteur personnel de médias, avec manipulation grâce au mobile.**

Lecteur universel desktop : vidéo, audio, PDF et texte dans une seule application.
Flutter + media_kit (libmpv), architecture « bus de commandes » prête pour la future télécommande mobile
([OMNIA-Mobile](https://github.com/steve20400/OMNIA-Mobile)).

> État : **les six phases du plan sont en place.**
> Fondations et thème ; playlist automatique du dossier ; confort de lecture (OSD, récents, menu
> contextuel, instance unique, aide) ; documents (PDF, texte, Markdown) ; fonctions avancées
> (sous-titres, pistes audio, capture, boucle A-B, image, égaliseur, vue audio, mini-lecteur) ;
> finitions (paramètres, éditeur de raccourcis, installateurs).
> Voir `DESIGN.md` pour le plan design.

## Plateformes

OMNIA s'installe sur **Windows** et **Linux (Ubuntu)** ; le code reste compatible macOS.
Un seul code source, aucune API spécifique à un système sans abstraction : les différences réelles
(codes d'erreur, position de fenêtre sous Wayland, bordures de redimensionnement, gestionnaire de
fichiers, touche système) sont isolées dans `lib/core/utils/`, `lib/core/services/` et
`lib/ui/shortcuts/`.

## Prérequis

Flutter stable ≥ 3.44 avec le support desktop activé.

### Windows

- Visual Studio 2022 avec le workload **« Développement Desktop en C++ »** (MSVC, CMake, Windows 10 SDK).
- **Mode développeur** activé, car les plugins Flutter utilisent des liens symboliques :

```bash
start ms-settings:developers
```

- Pour produire l'installateur : [Inno Setup 6](https://jrsoftware.org/isinfo.php) (commande `iscc`).

libmpv et pdfium sont embarqués par les paquets : rien d'autre à installer.

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

## Installation

### Windows

```bash
flutter build windows --release
iscc windows\installer\omnia.iss
```

L'installateur `build\installer\OMNIA-Setup-<version>.exe` propose l'installation pour tous ou pour soi seul,
un raccourci de bureau, et inscrit OMNIA dans **« Ouvrir avec »** pour chaque format lisible (42
extensions). Il ne détourne pas l'application par défaut : Windows 10 et 11 laissent ce choix à
l'utilisateur, dans *Paramètres › Applications › Applications par défaut*. La désinstallation retire
les associations.

La liste des extensions de l'installateur est générée depuis `MediaRouter`, la même source que le scan
de dossier ; un test vérifie qu'elles ne divergent pas. Après avoir ajouté un format :

```bash
python tool/make_installer_assoc.py
```

### Ubuntu

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

« Ouvrir avec → OMNIA » est ensuite proposé pour les formats audio, vidéo, PDF et texte.

### Icône

L'icône Windows (`windows/runner/resources/app_icon.ico`, 16 à 256 px) reprend le dessin de
`linux/dev.omnia.omnia.svg` : le faisceau du projecteur. Elle se régénère sans dépendance :

```bash
python tool/make_icon.py windows/runner/resources
```

## Qualité

```bash
flutter analyze   # doit être vierge
flutter test      # core, interface et intégration système
```

Les tests couvrent le bus et la sérialisation de chaque commande, le scan de dossier (1000 fichiers),
le tri naturel, la playlist, la reprise de lecture et ses trois politiques, l'historique, les
préférences (relecture tolérante, changements partiels), la table de raccourcis (conflits,
réaffectation, persistance), l'OSD, l'instance unique, l'encodage des textes, les contrôleurs de
documents, et l'écran Paramètres de bout en bout (du clic au stockage). Les fichiers d'installation
Windows et Linux, et le workflow de CI, sont vérifiés contre le code.

Aperçus des écrans, dessinés par le vrai code de l'interface, dans `build/preview/` :

```bash
OMNIA_PREVIEW=1 flutter test test/preview/screens_preview_test.dart
```

## Intégration continue

Chaque envoi sur `main` et chaque pull request lancent `.github/workflows/ci.yml` sur les machines de
GitHub. Il n'y a rien à installer : la compilation n'a pas besoin d'un poste de développement prêt.

| Tâche | Machine | Contenu |
|---|---|---|
| Analyse et tests | Ubuntu 24.04 | `flutter analyze`, `flutter test` |
| Windows | Windows Server 2025 | tests, compilation, installateur Inno Setup, lancement réel |
| Linux | Ubuntu 24.04 | compilation, archive `tar.gz`, lancement réel sur écran virtuel |

Le **lancement réel** démarre l'application compilée avec un son en argument, puis lui confie un PDF
par une seconde instance, comme un fichier déposé sur l'icône. Il vérifie que la fenêtre reste
ouverte, que la seconde instance se retire, et que les deux fichiers entrent dans l'historique. Il
prend une capture d'écran à chaque étape.

Les résultats se téléchargent en bas de la page de chaque exécution, onglet **Actions** du dépôt,
une fois connecté à GitHub : installateur Windows, version portable, archive Linux, captures du
lancement réel. L'archive Linux est un `tar.gz`, qui garde le droit d'exécution du binaire.

Un échec se lit sans ouvrir les journaux : la fin de la sortie de l'étape est publiée en annotation
sur la page de l'exécution, et chaque test échoué y apparaît avec son fichier, sa ligne et son
message. La version de Flutter est fixée dans le workflow (`FLUTTER_VERSION`), en accord avec la
contrainte de `pdfrx`.

## Structure du projet

```
lib/
  main.dart                 # initialisation (media_kit, instance unique, Hive, fenêtre)
  core/                     # logique pure, sans widget
    commands/               # PlayerCommand (sealed, JSON) + PlayerCommandBus
    controllers/            # MediaController, AvController (mpv), PdfController (pdfium),
                            # TextController, MediaRouter
    models/                 # PlaybackState, PlaylistState, AppPreferences, HistoryEntry, ResumeOffer…
    services/               # PlaybackService, PlaylistService, FolderScanner, HistoryStore,
                            # SettingsStore, WindowService, SystemIntegration, SingleInstance,
                            # ScreenWake, ScreenshotService, AudioMetadataService, local_storage
    utils/                  # timecodes, tri naturel, codes d'erreur OS, session Wayland, arguments CLI,
                            # encodage des textes, noms de captures
    providers.dart          # câblage Riverpod
  ui/
    app.dart                # MaterialApp, thème et langue (préférences), mémorisation de la fenêtre
    screens/player_screen.dart
    settings/               # écran Paramètres, contrôles, éditeur de raccourcis
    shortcuts/              # actions, table personnalisable, noms de touches, gestionnaire clavier
    widgets/                # barre de titre, contrôles, faisceau, scène, panneau, OSD, menus, aide,
                            # invite de reprise, mini-lecteur, vues document et audio
    osd/                    # modèle et contrôleur de l'affichage à l'écran
    theme/                  # OmniaColors, OmniaTypography, OmniaMotion, OmniaMetrics
    player_focus.dart       # retour du focus clavier au lecteur
  l10n/                     # app_fr.arb (défaut), app_en.arb
assets/fonts/               # Instrument Sans, IBM Plex Mono (embarquées)
linux/                      # dev.omnia.omnia.desktop, dev.omnia.omnia.svg, CMake (mimalloc)
windows/installer/          # omnia.iss (Inno Setup)
tool/                       # génération de l'icône et des associations de l'installateur
tool/ci/                    # scripts de la CI : annotations d'erreur, lancement réel, fichiers d'essai
.github/workflows/ci.yml    # intégration continue (analyse, tests, compilation, installateur)
test/                       # core, interface, intégration système
```

### Règle d'architecture

Toute action utilisateur devient une `PlayerCommand` publiée sur le `PlayerCommandBus` — y compris les
changements de réglages (`UpdatePreferences`, qui ne transporte que les réglages modifiés).
L'interface n'appelle **jamais** un contrôleur directement. Le `PlaybackService` écoute le bus, route
chaque commande (fenêtre, playlist, contrôleur de média actif, ou lui-même) et possède l'unique
`PlaybackState`, sérialisable en JSON, tout comme `PlaylistState` et `AppPreferences`. Brancher un
serveur WebSocket sur le bus suffira pour la télécommande mobile.

Seule exception, assumée : la table de raccourcis clavier s'enregistre directement. C'est la
configuration du clavier de ce poste, qu'une télécommande n'a pas à modifier.

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
- **Fichiers récents** : menu sous le bouton « Ouvrir » de la barre de titre, liste sur l'écran
  d'accueil et dans les paramètres. Un fichier est inscrit dès son ouverture ; un fichier déplacé reste
  listé, grisé.
- **Menu contextuel** (clic droit sur la scène) : lecture, fichier suivant/précédent, vitesse, fin de
  lecture, sous-titres, pistes audio, image, capture, boucle A-B, égaliseur, mini-lecteur, plein écran,
  premier plan, panneau, ouverture, emplacement du fichier, paramètres, aide.
- **Reprise de lecture** : automatique, proposée (« Reprendre à 12:34 ? », sans réponse la pastille
  s'efface et le fichier part du début) ou jamais, au choix. Pour un PDF, la page ; pour un texte, le
  défilement.
- **Instance unique** (désactivable) : « Ouvrir avec → OMNIA » alors qu'OMNIA tourne déjà réutilise la
  fenêtre existante et remplace la lecture en cours.
- **Glisser-déposer** : un fichier ou un dossier lâché sur la fenêtre, mini-lecteur compris, s'ouvre
  aussitôt. Lâché sur une icône qui lance OMNIA (raccourci du bureau, exécutable, lanceur `.desktop`
  quand le bureau Ubuntu accepte ce geste), il démarre l'application, ou il est confié à la fenêtre
  déjà ouverte, qui passe au premier plan. Parmi plusieurs
  fichiers, le premier lisible est ouvert. Un sous-titre lâché sur une vidéo se charge sur elle. Un
  document lâché sur le mini-lecteur rouvre la fenêtre entière.
- **Aide `F1`** : récapitulatif des raccourcis, lu dans la table de l'utilisateur.
- **Veille** : l'écran reste allumé tant qu'une vidéo joue, et seulement là.

## Vidéo et audio, en détail

- **Sous-titres** : les fichiers `.srt`, `.ass`, `.ssa`, `.vtt`, `.sub` du même dossier portant le même nom
  de base (avec ou sans suffixe de langue, `film.fr.srt`) sont chargés automatiquement par mpv
  (désactivable). Pistes intégrées et externes listées dans le menu « sous-titres » ; chargement manuel ;
  décalage par pas de 0,5 s, avec une valeur par défaut ; taille réglable ; `V` masque ou affiche sans
  oublier la piste choisie.
- **Pistes audio** : sélection dans le menu quand le fichier en a plusieurs.
- **Capture** (`S`) : PNG dans `Téléchargements/OMNIA` ou le dossier choisi, nom selon un motif
  (`{name}`, `{date}`, `{time}`, `{position}`) ; le chemin s'affiche dans l'OSD, un dossier inaccessible
  aussi ; deux captures dans la même seconde sont numérotées.
- **Boucle A-B** (`A`) : pose A, puis B, puis efface. Bornes marquées sur le faisceau ; mpv boucle lui-même
  entre les deux, à l'image près.
- **Image** : ratio (auto, 16:9, 4:3, remplir), zoom, rotation 90°, luminosité / contraste / saturation
  dans un panneau flottant. Réglages conservés d'un fichier à l'autre, zoom et rotation remis à zéro.
- **Égaliseur** 10 bandes (31 Hz à 16 kHz), préréglages Normal, Rock, Pop, Jazz, Classique, Basses,
  Aigus, Vocal, Électro, Acoustique, curseurs libres, activable sans perdre les réglages.
- **Vue audio** : pochette (ID3, Vorbis, MP4, APE, lue hors du fil de l'interface) en grand, fond flouté
  dérivé de la pochette sous un voile de velours, titre, artiste, album ; vinyle stylisé sans pochette.
- **Mini-lecteur** (`Ctrl+Maj+M`) : fenêtre compacte au premier plan (pochette, titre, faisceau,
  transport), la géométrie et l'état de premier plan sont rendus à la sortie.

## Documents (lecture seule)

**PDF** (pdfium via `pdfrx`) : défilement continu ou page par page, zoom `Ctrl+molette`, ajuster à la
largeur (`Ctrl+0`) ou à la page, aller à la page (`Ctrl+G`), recherche plein texte (`Ctrl+F`) avec
surlignage et navigation, rotation (`Ctrl+R`), mode sombre de lecture (`Ctrl+D`), sommaire et vignettes
dans le panneau latéral, dernière page lue mémorisée. Un PDF protégé par mot de passe affiche un message
clair : OMNIA ne demande jamais de secret.

**Texte** (`.txt`, `.log`) et **Markdown** (`.md`) : encodage détecté (UTF-8 avec ou sans BOM, UTF-16,
Windows-1252 en repli), taille de police `Ctrl+molette`, thème de lecture clair par défaut (une page se
lit sur du papier) ou sombre (`Ctrl+D`), recherche avec surlignage, position de défilement mémorisée.
Les fichiers de plus de 32 Mo sont tronqués à l'affichage.

Le panneau de dossier fonctionne à l'identique pour les documents : ouvrir un PDF montre les autres
PDF, textes et médias du dossier.

## Paramètres

Bouton ⚙ de la barre de titre, `Ctrl+,` ou menu contextuel. Une feuille posée sur la scène, fermée par
`Échap` ou un clic sur le voile. Tout est enregistré aussitôt.

| Section | Réglages |
|---|---|
| Général | Langue (système, français, anglais), thème (sombre, clair, système), comportement en fin de lecture, reprise de lecture (automatique, demander, jamais), une seule fenêtre |
| Lecture | Pas d'avance et de recul (5, 10, 30, 60 s), vitesse au démarrage, volume au démarrage (dernier utilisé ou fixe) |
| Sous-titres | Taille, chargement automatique, décalage par défaut |
| Audio | Égaliseur, préréglage |
| Documents | Défilement des PDF, mode sombre de lecture, taille du texte |
| Raccourcis | Éditeur complet (voir ci-dessous) |
| Captures | Dossier de destination, motif de nom avec aperçu |
| Historique | Fichiers récents (liste, effacer), positions mémorisées (effacer), tout effacer |

Les réglages changés en cours de lecture deviennent la préférence : dernier volume, taille des
sous-titres, égaliseur, mode sombre de lecture, mise en page des PDF, taille du texte.

## Raccourcis

Tous personnalisables dans *Paramètres › Raccourcis* : cliquer sur un raccourci, puis appuyer sur la
nouvelle combinaison. Une touche déjà prise est signalée (« Déjà utilisé par… »), avec le choix de la
reprendre ou d'annuler ; chaque action se rétablit seule, ou toutes d'un coup. Les infobulles, les menus
et l'aide `F1` affichent toujours la table en vigueur, dans la langue de l'interface.

Table par défaut :

| Touche | Action |
|---|---|
| `Espace` | Lecture / pause |
| `←` / `→` | Reculer / avancer du pas choisi (5 s par défaut) ; `Maj` : 30 s ; `Ctrl` : 60 s |
| `↑` / `↓` | Volume ±5 |
| `M` | Muet |
| `F` / double-clic | Plein écran (`Échap` pour sortir) |
| `N` / `P` | Fichier suivant / précédent |
| `+` / `-` / `=` | Vitesse + / − / 1× (reconnus au caractère, en AZERTY comme en QWERTY) |
| `L` | Mode de fin de lecture (cycle) |
| `T` | Toujours au premier plan |
| `Tab` | Afficher / masquer le panneau |
| `S` | Capture d'écran |
| `A` | Boucle A-B (A, puis B, puis effacer) |
| `V` | Sous-titres oui / non |
| `Ctrl+Maj+M` | Mini-lecteur |
| `Ctrl+O` / `Ctrl+Maj+O` | Ouvrir un fichier / un dossier |
| `Pg préc.` / `Pg suiv.` | Document : page précédente / suivante |
| `Ctrl+G` | Document : aller à la page |
| `Ctrl+F` | Document : rechercher |
| `Ctrl+molette` / `Ctrl+0` | Document : zoom / ajuster à la largeur |
| `Ctrl+R` / `Ctrl+D` | Document : pivoter / mode sombre de lecture |
| `Ctrl+,` | Paramètres |
| `F1` | Aide : récapitulatif des raccourcis |

`Échap` quitte un champ de recherche, ferme l'aide ou les paramètres, et sort du plein écran.
Molette sur la vidéo : volume. Clic simple : lecture/pause. Clic droit : menu contextuel.

## Compromis documentés

- **Sourdine** : media_kit n'expose pas d'API « mute » ; OMNIA écrit la propriété native mpv `mute`, ce qui préserve le volume réglé. Sur une plateforme sans `NativePlayer`, seul l'état visuel change.
- **Durées dans le panneau** : sonder la durée de chaque fichier au scan coûterait une ouverture mpv par fichier. OMNIA n'affiche donc une durée que lorsqu'elle est déjà connue par l'historique, et se rabat sinon sur la taille du fichier.
- **Position de fenêtre sous Wayland** : le protocole interdit à une application de connaître ou d'imposer sa position. OMNIA n'y mémorise que la taille et laisse le compositeur placer la fenêtre.
- **Bordures de fenêtre sous Linux** : masquer la barre de titre retire toutes les décorations GTK. OMNIA redessine donc ses propres bords de redimensionnement (`DragToResizeArea`), inutiles sur Windows et macOS qui gardent leur cadre natif.
- **`N` en fin de liste** : la touche « fichier suivant » reboucle au premier fichier, alors que la lecture automatique en mode « suivant » s'arrête. Une action explicite ne doit pas être sans effet ; un enchaînement automatique ne doit pas tourner en rond sans qu'on l'ait demandé (mode « boucler le dossier » pour cela).
- **Instance unique** : le brief suggère un socket local ou D-Bus sous Linux. Ni l'un ni l'autre n'existe sous Windows, alors qu'OMNIA doit s'y installer aussi. La première instance écoute donc sur un port de la boucle locale (`127.0.0.1`, jamais exposé au réseau), noté avec un secret aléatoire dans `instance.json` du dossier de données ; une seconde instance lit ce fichier, transmet ses arguments et se termine. Un verrou périmé (instance tuée) est détecté par l'échec de connexion et réécrit.
- **Plusieurs fenêtres** : quand l'instance unique est désactivée, la base de préférences reste tenue par la première fenêtre (Hive la verrouille). Les suivantes démarrent avec les réglages relus d'une copie en clair (`preferences.json`) et ne conservent pas leur historique. Le réglage lui-même est lu dans un fichier marqueur, avant toute base de données.
- **Reprise de lecture** : la position mémorisée est appliquée par un seek juste après le démarrage ; on peut apercevoir la première image un instant.
- **Dépôt sur la barre des tâches Windows** : lâcher un fichier sur le bouton épinglé d'OMNIA l'épingle à sa liste de raccourcis, sans l'ouvrir ; c'est le comportement de Windows pour toutes les applications. Survoler le bouton d'une fenêtre ouverte l'amène devant : il suffit alors de lâcher le fichier sur la fenêtre. Le raccourci du bureau, lui, accepte le dépôt.
- **Premier plan sous Ubuntu** : quand un fichier est confié à la fenêtre déjà ouverte, GNOME peut afficher la notification « OMNIA est prêt » au lieu d'amener la fenêtre devant ; c'est sa protection contre le vol de focus. Sous Windows, la seconde instance cède ce droit à la première avant de lui confier le fichier.
- **Associations Windows** : l'installateur inscrit OMNIA dans « Ouvrir avec » sans imposer l'application par défaut, que seul l'utilisateur peut choisir depuis Windows 10.
- **Chemins longs sous Windows** : le manifeste déclare `longPathAware`, mais Windows ne l'honore que si la stratégie système `LongPathsEnabled` est active.
- **Version de `pdfrx`** : les versions ≥ 2.6 exigent Dart 3.13 (Flutter 3.47) ; le projet reste sur la dernière version compatible avec Flutter 3.44 (`>=2.4.0 <2.6.0`). À relever avec le SDK.
- **Rotation d'un PDF en défilement continu** : `pdfrx` ne pivote pas sa vue continue ; OMNIA pivote la vue entière, le défilement suit donc l'axe des pages pivotées. En mode page par page, la rotation est native (`rotationOverride`).
- **Mode sombre de lecture des PDF** : inversion des couleurs suivie d'une rotation de teinte de 180° (« inversion intelligente »). Le papier devient sombre, l'encre claire, et les images gardent des teintes proches des originales — sans être préservées exactement, ce qu'aucun filtre matriciel ne permet.
- **Recherche en mode page par page** : le surlignage des occurrences n'est disponible qu'en défilement continu (il est rendu par la vue `pdfrx`) ; la barre de recherche fonctionne dans les deux modes.
- **Égaliseur** : appliqué par le filtre FFmpeg `equalizer` (une bande par fréquence, largeur d'une octave) via la propriété mpv `af`, remplacée à chaque réglage. C'est la voie la plus fiable que mpv offre ; si une version de mpv refuse la propriété, l'erreur est absorbée et le son continue sans égalisation. Les préréglages sont des courbes classiques, à affiner à l'oreille.
- **Réglages d'image** : luminosité, contraste et saturation utilisent les propriétés mpv du même nom ; selon le pilote vidéo (`gpu` ou non), certaines sorties les ignorent.
- **Capture** : `media_kit` rend l'image via mpv sans les sous-titres libass ; la capture reflète l'image seule.
- **Motif de nom des captures** : les jetons s'affichent tels quels dans l'écran Paramètres ; seule leur description est traduite, pour qu'un motif écrit en français fonctionne aussi en anglais.
