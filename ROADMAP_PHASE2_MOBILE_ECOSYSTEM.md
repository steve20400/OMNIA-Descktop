# Feuille de Route OMNIA : Écosystème Multiplateforme & Synchronisation Locale (Phases 1, 2 & 3)

Ce document formalise les spécifications techniques, l'architecture logicielle et les jalons de développement du projet **OMNIA**, depuis la consolidation du lecteur de bureau jusqu'à l'application mobile autonome et le protocole de communication en réseau local (Zero-Internet).

---

## 1. Phase 1 : Consolidation & Parachèvement de la Version Bureau (Desktop)

Avant toute distribution sur l'Ubuntu App Center et avant d'entamer la version mobile, la version bureau intègre les finitions suivantes :

### 1.1 Mini-Lecteur Universel Multi-Médias
- **Prise en charge de tous les formats** : Le mini-lecteur compact et toujours au premier plan (*Always-on-Top*) ne se limite plus aux vidéos et audios :
  - **Images** : Affichage compact centré avec maintien du ratio et zoom direct.
  - **Documents (PDF, Bureautique PPTX/DOCX/ODP, Textes & Code)** : Vue compacte de lecture rapide, défilement à la molette et raccourcis de navigation.
- **Accès universel** : Intégration du bouton mini-lecteur dans la barre de documents (`DocumentBar`) et la barre d'images (`ImageBar`), en plus du raccourci universel (`Ctrl+M` / `Ctrl+Shift+M`).

### 1.2 Panneau de Liste Inférieur en Mode Mini-Lecteur (Style YouTube Mini-Player)
- **Tiroir inférieur contextuel** : Lorsque le mini-lecteur est actif, l'ouverture de la liste de lecture (via la touche `Tab` ou le bouton playlist) ne déploie pas un panneau latéral gauche inadapté aux dimensions compactes, mais déploie un **tiroir vertical coulissant par le bas**, calqué sur l'ergonomie du mini-lecteur YouTube.
- **Filtres complets** : Accès direct aux filtres par type : *Tout*, *Vidéos*, *Audios*, *Documents* et *Images*.

### 1.3 Édition & Modification de Documents en Mode Mini-Lecteur
- **Bouton Modifier & Enregistrer actif en mini-lecteur** : Les documents modifiables (texte brut, code source, markdown) peuvent être modifiés directement depuis la fenêtre compacte.
- **Bascule fluide lecture/édition** : En mode lecture, la fenêtre reste déplaçable au doigt/à la souris ; en mode édition, le champ de saisie prend la main pour permettre la frappe et les sélections sans friction.
- **Enregistrement direct** : Sauvegarde instantanée sur le disque avec raccourci `Ctrl+S` ou bouton dédié.

### 1.4 Suite de Retouche & Redimensionnement d'Images (Non-Destructif)
- **Outil d'ajustement complet** : Accessible en mode normal et en mini-lecteur (`Icons.tune_rounded`).
- **Redimensionnement sur mesure** : Ajustement largeur × hauteur en pixels avec verrouillage de proportions et boutons d'échelle rapide (25 %, 50 %, 75 %, 100 %, 150 %, 200 %).
- **Retouche des couleurs** : Réglages précis de luminosité (-100 % à +100 %), de contraste (0 % à 200 %) et de saturation (0 % à 200 %, avec passage noir & blanc).
- **Orientation & Filtres** : Rotation 90°, miroir horizontal/vertical, filtres Noir & Blanc, Sépia et Négatif avec prévisualisation en temps réel.
- **Sauvegarde non-destructive d'une nouvelle copie** : L'image originale n'est JAMAIS écrasée. Une copie propre (suffixe paramétrable, ex: `_modifié`) est générée, et l'application bascule automatiquement la lecture sur cette nouvelle copie.

### 1.5 Barres d'Outils Adaptatives & Menu 3 Points (« ... »)
- **Menu overflow compact** : Sur toutes les barres d'outils, lorsque la fenêtre est rétrécie ou en mini-lecteur compact, les commandes secondaires se regroupent automatiquement dans le menu 3 points (`Icons.more_horiz_rounded`).
- **Restauration automatique** : Dès que la fenêtre est agrandie, toutes les icônes reprennent naturellement leur place en ligne sans surcharge.

---

## 2. Phase 2 : Application OMNIA Mobile Autonome (Android / iOS)

L'application mobile sera développée sous Flutter dans un environnement dédié, en tant qu'application de lecture universelle autonome complète avant toute interconnexion.

### 2.1 Capacités Fondamentales
- **Prise en charge universelle** : Lecture identique au bureau (Vidéos, Audios Hi-Res, Images, PDF, Présentations PPTX/ODP, Documents Word DOCX/ODT, Textes & Code).
- **Édition et enregistrement sur stockage mobile** : Modification directe des fichiers texte et code, et sauvegarde transparente.
- **Retouche et redimensionnement d'images sur mobile** : Suite intégrée identique au bureau permettant de recadrer, redimensionner, ajuster les couleurs et exporter une copie sans toucher au fichier d'origine de la galerie.
- **Barres contextuelles et menu 3 points mobile** : Adaptation dynamique des barres d'outils selon l'orientation portrait/paysage et la taille de l'écran avec menu overflow « ... ».
- **Intégration au système d'exploitation** : Déclaration des intent-filters Android et types UTType iOS pour figurer dans la boîte de dialogue « Ouvrir avec » pour chaque extension prise en charge.

### 2.2 Ergonomie & Expérience Utilisateur Mobile
- **Picture-in-Picture (PiP) & Mini-Lecteur Flottant** :
  - Support du PiP natif Android/iOS permettant à la vidéo de continuer à flotter au-dessus de n'importe quelle autre application du téléphone.
  - Mini-lecteur interne rétractable en bas de l'écran avec tiroir de playlist inférieur.
- **Lecture audio en arrière-plan** :
  - Possibilité de continuer à écouter le flux audio d'une vidéo avec l'écran éteint ou l'application minimisée (mode « Écoute seule »).
- **Contrôles gestuels tactiles avancés** :
  - Glissement vertical gauche : Réglage de la luminosité de l'écran.
  - Glissement vertical droit : Réglage du volume sonore.
  - Glissement horizontal : Recherche temporelle précise (*scrubbing*).
  - Double-tap gauche/droit : Saut rapide de ±10 secondes.
  - Pincement pour zoomer (*pinch-to-zoom*) sur les vidéos et les images.

---

## 3. Phase 3 : Protocole de Communication Réseau Local OMNIA Connect (Zero-Internet)

Ce volet permet la synchronisation fluide entre Desktop et Mobile sans jamais nécessiter de connexion Internet (fonctionnement exclusif en Wi-Fi local, point d'accès/hotspot mobile ou Bluetooth direct).

### 3.1 Appairage Instantané Sécurisé par QR Code Bidirectionnel
- **Association sans saisie manuelle** :
  - L'écran Desktop génère un QR code dynamique contenant l'adresse IP locale, le port éphémère et un jeton de session cryptographique.
  - Le mobile scanne le QR code du PC pour s'associer instantanément.
  - **Réciprocité complète** : Si l'ordinateur possède une webcam ou que le point d'accès est créé par le PC, le mobile peut également afficher son propre QR code scannable par le desktop.

### 3.2 Projection & Miroir Bidirectionnel (« Projeter »)
- **Mobile ➔ Desktop** :
  - Un bouton **« Projeter »** sur l'application mobile transfère l'affichage et la lecture en cours vers le grand écran du bureau.
  - Le mobile sert alors de télécommande tactile interactive : mise en pause, barre de progression, réglage du volume, défilement de documents.
- **Desktop ➔ Mobile** :
  - Un bouton **« Projeter sur Mobile »** sur l'ordinateur transmet le flux de lecture vers le téléphone pour continuer à regarder ou lire en se déplaçant dans la pièce.
- **Synchronisation d'état en temps réel** : Utilisation d'un canal WebSockets local ultra-rapide à faible latence (protocole binaire JSON/MessagePack) synchronisant position temporelle, volume, vitesse et page de document.

### 3.3 Accès aux Médias Distants sans Téléchargement Obligatoire
- **Exploration du disque distant** : L'utilisateur sur mobile peut parcourir les dossiers partagés de l'ordinateur directement depuis l'interface OMNIA.
- **Streaming local direct** : Lecture instantanée en flux continu sans obliger l'utilisateur à télécharger l'intégralité du fichier volumineux avant de le lire.
- **Option de copie hors-ligne** : Possibilité optionnelle de télécharger le fichier sur la mémoire locale du téléphone pour un visionnage ultérieur hors du réseau.

---

## 4. Phase 4 : Synergie Écosystème & Promotion Croisée

### 4.1 Proposition Intelligente de la Version Bureau
- Pour un utilisateur ayant installé uniquement la version mobile :
  - Section dédiée dans les Paramètres avec lien et QR code de téléchargement de la version bureau.
  - Notification discrète périodique (tous les 7 jours) suggérant de découvrir la version PC.
  - Options respectueuses : « Me rappeler plus tard » (délai de 2 jours), « Ne plus afficher » (désactivation permanente) et masquage automatique définitif dès qu'une connexion avec un PC a été établie.

### 4.2 Perspective Future (R&D)
- Étude technique pour étendre le protocole OMNIA Connect aux topologies Mobile-Mobile et Desktop-Desktop.

---
*Auteur : STEVE AUREL MANFO — Tous droits réservés.*
