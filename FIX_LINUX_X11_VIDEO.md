# Spécification Technique & Prompt d'Implémentation : Correction de l'affichage vidéo sous Linux (X11 / GPU Legacy)

> **Projet :** OMNIA-Descktop  
> **Composant ciblé :** Moteur de rendu vidéo (`media_kit_video` / Linux GTK Embedder)  
> **Document :** Cahier des charges et prompt de développement clé en main  

---

## 1. Contexte et Cause Racine : Pourquoi cette modification est nécessaire

### Le Problème Observé
Lors de l'exécution d'OMNIA sous Linux (notamment sur des machines dotées de circuits graphiques Intel de 2ᵉ génération comme l'Intel HD Graphics 3000 d'un Dell Latitude E6420, ou toute distribution configurée sous X11) :
- Le fichier vidéo se charge correctement.
- **L'audio se lit parfaitement.**
- **L'écran vidéo reste désespérément noir.**
- Le terminal affiche les avertissements suivants :
  ```text
  media_kit: VideoOutput: EGL display or context is invalid.
  media_kit: VideoOutput: S/W rendering.
  ** (dev.omnia.omnia): WARNING **: Timed out waiting for OpenGL frame of size ...
  ```
- À la fermeture de la fenêtre, l'application se termine par un crash :
  ```text
  g_mutex_clear() called on uninitialised or locked mutex
  Erreur de segmentation (core dumped)
  ```

---

### La Cause Racine Technique (Post-Mortem)

1. **La session d'affichage X11 (Xorg) :**  
   Ubuntu et de nombreuses distributions Linux désactivent Wayland par défaut sur les chipsets graphiques plus anciens (Intel Sandy Bridge / HD 3000, NVIDIA avec certains pilotes propriétaires, etc.) pour basculer sur une session **X11**.

2. **L'incompatibilité de `media_kit_video 2.0.1` avec X11 :**  
   Dans son code natif Linux (`media_kit_video/linux/video_output.cc`), le plugin tente de récupérer le contexte graphique de Flutter via les API standards EGL :
   ```cpp
   EGLDisplay flutter_display = eglGetCurrentDisplay();
   EGLContext flutter_context = eglGetCurrentContext();
   ```
   **Le nœud du problème :** Sous X11, le thread principal de GTK3 utilise **GLX** (et non EGL). Par conséquent, aucun contexte EGL n'est courant sur ce thread (`flutter_context == EGL_NO_CONTEXT`).  
   Le plugin en déduit à tort que le matériel est incapable d'accélération matérielle et journalise :
   `media_kit: VideoOutput: EGL display or context is invalid.`

3. **L'échec du repli logiciel (S/W rendering) :**  
   `media_kit_video` bascule alors en rendu logiciel CPU (`FlPixelBufferTexture`). Cependant :
   - Le moteur Flutter Linux Embedder attend une trame de synchronisation qui ne vient jamais : `Timed out waiting for OpenGL frame`. L'image reste noire.
   - Les mutex internes de `media_kit_video` pour la copie des pixels logiciels ne sont pas correctement synchronisés avec la destruction de la fenêtre GTK, provoquant un double `clear` de mutex et un crash par `SIGSEGV` (core dump) à la fermeture.

**Conclusion :** Sans patch natif, `media_kit_video 2.0.1` est dans l'incapacité totale d'afficher une vidéo sur n'importe quel poste Linux exécutant une session X11.

---

## 2. La Solution d'Ingénierie : Vendoring & Patch Natif

La solution adoptée par les projets multimédias Flutter sous Linux (comme *Glassfin* et *Namida*) consiste à :
1. **Isoler `media_kit_video` en local** dans le dépôt (`third_party/media_kit_video`) et le déclarer via `dependency_overrides` dans `pubspec.yaml`.
2. **Obtenir le display EGL depuis GDK** : Sous X11 comme sous Wayland, le moteur Linux de Flutter construit son display EGL à partir de la connexion native GDK (`gdk_x11_display_get_xdisplay()` et `eglGetPlatformDisplayEXT()`).
3. **Créer un contexte EGL isolé pour mpv** avec les mêmes attributs graphiques que Flutter, en libérant temporairement le contexte GLX de GTK le temps de l'initialisation pour éviter les erreurs `EGL_BAD_ACCESS`.

---

## 3. Le Prompt Professionnel pour Réaliser la Modification

*Copiez-collez l'intégralité du bloc ci-dessous dans votre invite lorsque vous débuterez les travaux sur le code.*

````markdown
### PROMPT DE MISSION : Correction du rendu vidéo Linux X11 dans OMNIA-Descktop

Tu es un ingénieur expert Flutter Desktop (Linux GTK / C++) et spécialiste du moteur multimédia libmpv / media_kit.

#### Contexte du problème
Dans notre application OMNIA (lecteur multimédia universel Flutter), la lecture vidéo sur les distributions Linux exécutant une session X11 (Xorg) produit un écran noir avec uniquement le son audible, accompagné du log :
`media_kit: VideoOutput: EGL display or context is invalid.` suivi de `media_kit: VideoOutput: S/W rendering.` puis d'un blocage `Timed out waiting for OpenGL frame` et d'un crash à la fermeture (`g_mutex_clear() on uninitialised mutex`).

Ce comportement est dû à `media_kit_video 2.0.1` qui utilise `eglGetCurrentContext()` sur le thread principal GTK (qui tourne sous GLX sur X11). Aucun contexte EGL n'étant courant, l'accélération matérielle échoue et le fallback logiciel gèle sous GTK.

#### Objectif
Mettre en place une version vendorée et patchée de `media_kit_video` dans `third_party/media_kit_video`, référencée via `dependency_overrides` dans `pubspec.yaml`, afin de garantir une accélération matérielle fluide (`H/W rendering`) sous X11 comme sous Wayland.

#### Cahier des charges strict
1. Ne pas réécrire la logique métier d'OMNIA (`lib/`).
2. Conserver la compatibilité totale avec les autres plateformes (Windows, macOS).
3. Vendoriser `media_kit_video` version 2.0.1 dans `third_party/media_kit_video`.
4. Appliquer le patch de récupération du display EGL natif GDK sous `linux/video_output.cc` et `linux/texture_gl.cc`.
5. Valider la compilation locale Linux via `flutter pub get` et `flutter analyze`.

---

#### Étapes de mise en œuvre détaillées

##### Étape 1 : Téléchargement et intégration des sources du plugin
Télécharger les sources exactes du package `media_kit_video: 2.0.1` depuis pub.dev ou GitHub et les placer dans :
`third_party/media_kit_video/`

##### Étape 2 : Patch de `third_party/media_kit_video/linux/video_output.cc`
Ajouter la détection du display EGL via GDK Display :
```cpp
#include <epoxy/egl.h>
#include <epoxy/glx.h>
#include <gdk/gdkwayland.h>
#include <gdk/gdkx.h>

// Récupération de l'EGLDisplay Flutter depuis la connexion native GDK
static EGLDisplay get_flutter_egl_display() {
  GdkDisplay* display = gdk_display_get_default();
  EGLDisplay egl_display = EGL_NO_DISPLAY;
  if (GDK_IS_WAYLAND_DISPLAY(display)) {
    egl_display = eglGetPlatformDisplayEXT(
        EGL_PLATFORM_WAYLAND_EXT, gdk_wayland_display_get_wl_display(display), NULL);
  } else if (GDK_IS_X11_DISPLAY(display)) {
    egl_display = eglGetPlatformDisplayEXT(
        EGL_PLATFORM_X11_EXT, gdk_x11_display_get_xdisplay(display), NULL);
  }
  if (egl_display == EGL_NO_DISPLAY) {
    g_printerr("media_kit: VideoOutput: Could not get Flutter's EGL display from GDK.\n");
    return EGL_NO_DISPLAY;
  }
  if (!eglInitialize(egl_display, NULL, NULL)) {
    g_printerr("media_kit: VideoOutput: Failed to initialise Flutter's EGL display.\n");
    return EGL_NO_DISPLAY;
  }
  return egl_display;
}

// Sélection d'une configuration EGL compatible avec Flutter
static EGLConfig choose_flutter_egl_config(EGLDisplay egl_display) {
  const EGLint attributes[] = {
      EGL_RED_SIZE,   8, EGL_GREEN_SIZE,   8,
      EGL_BLUE_SIZE,  8, EGL_ALPHA_SIZE,   8,
      EGL_DEPTH_SIZE, 8, EGL_STENCIL_SIZE, 8,
      EGL_NONE
  };
  EGLConfig config = NULL;
  EGLint num_configs = 0;
  if (!eglChooseConfig(egl_display, attributes, &config, 1, &num_configs) || num_configs < 1) {
    g_printerr("media_kit: VideoOutput: No EGL config matching Flutter's.\n");
    return NULL;
  }
  return config;
}

// Gestion des contextes pour éviter EGL_BAD_ACCESS sous X11/GLX
static GdkGLContext* release_gdk_gl_context() {
  GdkGLContext* context = gdk_gl_context_get_current();
  if (context != NULL) {
    g_object_ref(context);
    gdk_gl_context_clear_current();
  }
  return context;
}

static void restore_gdk_gl_context(GdkGLContext* context) {
  if (context != NULL) {
    gdk_gl_context_make_current(context);
    g_object_unref(context);
  }
}
```

Dans la fonction `video_output_new()` :
Remplacer le bloc `if (flutter_display != EGL_NO_DISPLAY && flutter_context != EGL_NO_CONTEXT)` par :
- Si `flutter_display == EGL_NO_DISPLAY`, appeler `get_flutter_egl_display()`.
- Utiliser `choose_flutter_egl_config()` lorsque le contexte actuel n'est pas interrogable via `eglQueryContext`.
- Encadrer l'activation du contexte EGL isolé avec `release_gdk_gl_context()` et `restore_gdk_gl_context()`.

Dans `video_output_dispose()` :
Ne pas appeler `glDeleteTextures` ou libérer le nom de texture si aucun contexte EGL n'est courant pour éviter d'invoquer le contexte GLX de GTK.

##### Étape 3 : Mise à jour de `pubspec.yaml`
Ajouter la surcharge suivante au niveau racine de `pubspec.yaml` :
```yaml
dependency_overrides:
  media_kit_video:
    path: third_party/media_kit_video
```

##### Étape 4 : Validation
1. Lancer `flutter pub get`.
2. Lancer `flutter analyze` pour vérifier qu'aucune régression Dart n'a été introduite.
3. Compiler le paquet Linux :
   ```bash
   flutter build linux --release
   ```
4. Exécuter le binaire sur une vidéo en session X11 :
   ```bash
   GDK_BACKEND=x11 ./build/linux/x64/release/bundle/omnia /chemin/vers/video.mp4
   ```
5. Confirmer dans les logs la présence de :
   `media_kit: VideoOutput: H/W rendering with isolated EGL context.`
   et l'affichage fluide et sans saccade de l'image vidéo.
````

---

## 4. Récapitulatif des Bénéfices pour OMNIA

- **Compatibilité universelle Linux :** OMNIA devient 100% fonctionnel sur tous les environnements de bureau (GNOME Wayland, GNOME X11, KDE, XFCE, Cinnamon, MATE).
- **Prise en charge des PC portables plus anciens :** Permet la lecture vidéo matérielle fluide sur les circuits intégrés Intel HD 3000 / 4000 très répandus.
- **Zéro régression Windows & macOS :** Le patch ne concerne que les fichiers C++ du dossier `linux/` de `media_kit_video`.
