// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'OMNIA';

  @override
  String get emptyStageHint => 'Déposez un fichier ou un dossier ici';

  @override
  String get emptyStageSubtitle =>
      'Vidéo, audio, PDF et texte — tout se lit ici.';

  @override
  String get openFile => 'Ouvrir un fichier';

  @override
  String get openFolder => 'Ouvrir un dossier';

  @override
  String get dropToPlay => 'Déposer pour lire';

  @override
  String get play => 'Lecture';

  @override
  String get pause => 'Pause';

  @override
  String get mute => 'Couper le son';

  @override
  String get unmute => 'Rétablir le son';

  @override
  String get fullscreen => 'Plein écran';

  @override
  String get exitFullscreen => 'Quitter le plein écran';

  @override
  String get minimize => 'Réduire';

  @override
  String get maximize => 'Agrandir';

  @override
  String get restore => 'Restaurer';

  @override
  String get closeWindow => 'Fermer';

  @override
  String get alwaysOnTop => 'Toujours au premier plan';

  @override
  String get loading => 'Ouverture…';

  @override
  String get audioOnly => 'Audio';

  @override
  String speedValue(String speed) {
    return '$speed×';
  }

  @override
  String get resetSpeed => 'Vitesse normale';

  @override
  String get showRemainingTime => 'Afficher le temps restant';

  @override
  String get showTotalTime => 'Afficher la durée totale';

  @override
  String get errorTitle => 'Impossible de lire ce fichier';

  @override
  String get errorFileNotFound =>
      'Le fichier est introuvable. Il a peut-être été déplacé ou supprimé.';

  @override
  String get errorUnsupported =>
      'Ce type de fichier n\'est pas pris en charge par OMNIA.';

  @override
  String get errorDecode =>
      'Le fichier semble endommagé, ou son format n\'est pas lisible par le moteur.';

  @override
  String get errorPermission =>
      'OMNIA n\'a pas l\'autorisation de lire ce fichier ou ce dossier.';

  @override
  String get errorEmptyFolder =>
      'Ce dossier ne contient aucun fichier qu\'OMNIA sache lire.';

  @override
  String get errorUnknown =>
      'Une erreur inattendue s\'est produite pendant la lecture.';

  @override
  String get errorHint =>
      'Vous pouvez ouvrir un autre fichier, ou déposer un fichier ici.';

  @override
  String get openAnotherFile => 'Ouvrir un autre fichier';

  @override
  String get panelShow => 'Afficher le panneau';

  @override
  String get panelHide => 'Masquer le panneau';

  @override
  String get panelSearchPlaceholder => 'Rechercher dans le dossier';

  @override
  String get panelScanning => 'Analyse du dossier…';

  @override
  String get panelEmpty => 'Aucun fichier lisible dans ce dossier';

  @override
  String panelNoResults(String query) {
    return 'Aucun résultat pour « $query »';
  }

  @override
  String get panelNoFolder => 'Ouvrez un fichier pour voir ses voisins';

  @override
  String panelFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers',
      one: '1 fichier',
      zero: 'aucun fichier',
    );
    return '$_temp0';
  }

  @override
  String panelFileCountFiltered(int visible, int total) {
    return '$visible sur $total';
  }

  @override
  String get filterAll => 'Tous';

  @override
  String get filterVideo => 'Vidéo';

  @override
  String get filterAudio => 'Audio';

  @override
  String get filterDocuments => 'Documents';

  @override
  String get sortLabel => 'Trier';

  @override
  String get sortName => 'Nom';

  @override
  String get sortDate => 'Date';

  @override
  String get sortSize => 'Taille';

  @override
  String get sortType => 'Type';

  @override
  String get sortAscending => 'Ordre croissant';

  @override
  String get sortDescending => 'Ordre décroissant';

  @override
  String get contextPlay => 'Lire';

  @override
  String get contextRemove => 'Retirer de la liste';

  @override
  String get contextReveal => 'Ouvrir l\'emplacement du fichier';

  @override
  String get badgeWatched => 'Déjà lu';

  @override
  String badgeResume(String time) {
    return 'Reprendre à $time';
  }

  @override
  String get nextFile => 'Fichier suivant';

  @override
  String get previousFile => 'Fichier précédent';

  @override
  String get endModeLabel => 'En fin de lecture';

  @override
  String get endModeStop => 'S\'arrêter';

  @override
  String get endModeNext => 'Fichier suivant';

  @override
  String get endModeRepeatOne => 'Répéter le fichier';

  @override
  String get endModeLoopFolder => 'Boucler le dossier';

  @override
  String get endModeShuffle => 'Lecture aléatoire';

  @override
  String get clearSearch => 'Effacer la recherche';

  @override
  String get resizePanel => 'Redimensionner le panneau';

  @override
  String get osdMuted => 'Muet';

  @override
  String osdVolume(int volume) {
    return '$volume';
  }

  @override
  String get osdAlwaysOnTopOn => 'Toujours au premier plan';

  @override
  String get osdAlwaysOnTopOff => 'Premier plan désactivé';

  @override
  String get menuSpeed => 'Vitesse';

  @override
  String get recentFiles => 'Fichiers récents';

  @override
  String get clearRecent => 'Effacer les récents';

  @override
  String get noRecentFiles => 'Aucun fichier récent';

  @override
  String get recentMissing => 'Fichier introuvable';

  @override
  String get helpTitle => 'Raccourcis clavier';

  @override
  String get helpClose => 'Fermer l\'aide';

  @override
  String get helpSubtitle =>
      'Tout se pilote au clavier. Ces raccourcis seront personnalisables dans les paramètres.';

  @override
  String get helpGroupPlayback => 'Lecture';

  @override
  String get helpGroupNavigation => 'Navigation';

  @override
  String get helpGroupWindow => 'Fenêtre';

  @override
  String get helpPlayPause => 'Lecture / pause';

  @override
  String get helpSeekShort => 'Reculer / avancer de 5 s';

  @override
  String get helpSeekMedium => 'Reculer / avancer de 30 s';

  @override
  String get helpSeekLong => 'Reculer / avancer de 60 s';

  @override
  String get helpVolume => 'Volume + / −';

  @override
  String get helpSpeed => 'Vitesse + / −';

  @override
  String get helpPanelToggle => 'Afficher / masquer le panneau';

  @override
  String get helpLeaveSearch => 'Quitter la recherche';

  @override
  String get errorProtectedDocument =>
      'Ce document est protégé par un mot de passe. OMNIA ne peut pas l\'ouvrir.';

  @override
  String get docPageLabel => 'Page';

  @override
  String docPageOf(int page, int total) {
    return '$page / $total';
  }

  @override
  String get docGoToPage => 'Aller à la page';

  @override
  String get docPreviousPage => 'Page précédente';

  @override
  String get docNextPage => 'Page suivante';

  @override
  String get docZoomIn => 'Agrandir';

  @override
  String get docZoomOut => 'Réduire';

  @override
  String docZoomValue(int percent) {
    return '$percent %';
  }

  @override
  String get docFitWidth => 'Ajuster à la largeur';

  @override
  String get docFitPage => 'Ajuster à la page';

  @override
  String get docRotate => 'Pivoter de 90°';

  @override
  String get docReadingDark => 'Mode sombre de lecture';

  @override
  String get docLayoutContinuous => 'Défilement continu';

  @override
  String get docLayoutPaged => 'Page par page';

  @override
  String get docFind => 'Rechercher';

  @override
  String get docFontSize => 'Taille du texte';

  @override
  String docEncoding(String encoding) {
    return 'Encodage : $encoding';
  }

  @override
  String docLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lignes',
      one: '1 ligne',
      zero: 'aucune ligne',
    );
    return '$_temp0';
  }

  @override
  String get findPlaceholder => 'Rechercher dans le document';

  @override
  String findMatches(int index, int count) {
    return '$index / $count';
  }

  @override
  String get findNoMatch => 'Aucun résultat';

  @override
  String get findNext => 'Résultat suivant';

  @override
  String get findPrevious => 'Résultat précédent';

  @override
  String get findClose => 'Fermer la recherche';

  @override
  String get panelTabFolder => 'Dossier';

  @override
  String get panelTabOutline => 'Sommaire';

  @override
  String get panelTabPages => 'Pages';

  @override
  String get docNoOutline => 'Ce document n\'a pas de sommaire';

  @override
  String get docLoading => 'Chargement du document…';

  @override
  String get helpGroupDocuments => 'Documents';

  @override
  String get subtitles => 'Sous-titres';

  @override
  String get subtitlesOff => 'Sous-titres désactivés';

  @override
  String get subtitlesNone => 'Aucun';

  @override
  String get subtitlesLoadFile => 'Charger un fichier de sous-titres…';

  @override
  String get subtitleDelay => 'Décalage';

  @override
  String subtitleDelayValue(String seconds) {
    return '$seconds s';
  }

  @override
  String get subtitleSize => 'Taille des sous-titres';

  @override
  String get audioTracks => 'Piste audio';

  @override
  String get audioTrackAuto => 'Automatique';

  @override
  String get noTracks => 'Aucune piste';

  @override
  String get abLoop => 'Boucle A-B';

  @override
  String get abLoopSetA => 'Point A posé';

  @override
  String get abLoopSetB => 'Boucle A-B active';

  @override
  String get abLoopCleared => 'Boucle A-B désactivée';

  @override
  String get screenshot => 'Capture d\'écran';

  @override
  String get screenshotSaved => 'Capture enregistrée';

  @override
  String get image => 'Image';

  @override
  String get aspectRatio => 'Ratio d\'aspect';

  @override
  String get aspectAuto => 'Automatique';

  @override
  String get aspectWide => '16:9';

  @override
  String get aspectStandard => '4:3';

  @override
  String get aspectFill => 'Remplir';

  @override
  String get videoZoom => 'Zoom vidéo';

  @override
  String videoZoomValue(int percent) {
    return 'Zoom $percent %';
  }

  @override
  String get videoZoomReset => 'Zoom normal';

  @override
  String get videoRotate => 'Pivoter la vidéo';

  @override
  String videoRotation(int degrees) {
    return 'Rotation $degrees°';
  }

  @override
  String get imageAdjust => 'Réglages d\'image…';

  @override
  String get brightness => 'Luminosité';

  @override
  String get contrast => 'Contraste';

  @override
  String get saturation => 'Saturation';

  @override
  String get resetAdjust => 'Réinitialiser';

  @override
  String get equalizer => 'Égaliseur';

  @override
  String get equalizerOn => 'Égaliseur activé';

  @override
  String get equalizerOff => 'Égaliseur désactivé';

  @override
  String get equalizerPreset => 'Préréglage';

  @override
  String get presetNormal => 'Normal';

  @override
  String get presetRock => 'Rock';

  @override
  String get presetPop => 'Pop';

  @override
  String get presetJazz => 'Jazz';

  @override
  String get presetClassical => 'Classique';

  @override
  String get presetBass => 'Basses';

  @override
  String get presetTreble => 'Aigus';

  @override
  String get presetVocal => 'Vocal';

  @override
  String get presetElectronic => 'Électro';

  @override
  String get presetAcoustic => 'Acoustique';

  @override
  String get presetCustom => 'Personnalisé';

  @override
  String get miniPlayer => 'Mini-lecteur';

  @override
  String get miniPlayerExit => 'Quitter le mini-lecteur';

  @override
  String get unknownArtist => 'Artiste inconnu';

  @override
  String get closePanel => 'Fermer';

  @override
  String get screenshotFailed => 'Capture impossible';

  @override
  String get screenshotFailedHint =>
      'Le dossier des captures est inaccessible. Choisissez-en un autre dans les paramètres.';
}
