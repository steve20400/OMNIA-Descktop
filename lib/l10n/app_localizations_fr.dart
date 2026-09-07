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
}
