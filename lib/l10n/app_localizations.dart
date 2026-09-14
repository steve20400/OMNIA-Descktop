import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In fr, this message translates to:
  /// **'OMNIA'**
  String get appTitle;

  /// No description provided for @emptyStageHint.
  ///
  /// In fr, this message translates to:
  /// **'Déposez un fichier ou un dossier ici'**
  String get emptyStageHint;

  /// No description provided for @emptyStageSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Vidéo, audio, PDF et texte — tout se lit ici.'**
  String get emptyStageSubtitle;

  /// No description provided for @openFile.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir un fichier'**
  String get openFile;

  /// No description provided for @openFolder.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir un dossier'**
  String get openFolder;

  /// No description provided for @dropToPlay.
  ///
  /// In fr, this message translates to:
  /// **'Déposer pour lire'**
  String get dropToPlay;

  /// No description provided for @play.
  ///
  /// In fr, this message translates to:
  /// **'Lecture'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In fr, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @mute.
  ///
  /// In fr, this message translates to:
  /// **'Couper le son'**
  String get mute;

  /// No description provided for @unmute.
  ///
  /// In fr, this message translates to:
  /// **'Rétablir le son'**
  String get unmute;

  /// No description provided for @fullscreen.
  ///
  /// In fr, this message translates to:
  /// **'Plein écran'**
  String get fullscreen;

  /// No description provided for @exitFullscreen.
  ///
  /// In fr, this message translates to:
  /// **'Quitter le plein écran'**
  String get exitFullscreen;

  /// No description provided for @minimize.
  ///
  /// In fr, this message translates to:
  /// **'Réduire'**
  String get minimize;

  /// No description provided for @maximize.
  ///
  /// In fr, this message translates to:
  /// **'Agrandir'**
  String get maximize;

  /// No description provided for @restore.
  ///
  /// In fr, this message translates to:
  /// **'Restaurer'**
  String get restore;

  /// No description provided for @closeWindow.
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get closeWindow;

  /// No description provided for @alwaysOnTop.
  ///
  /// In fr, this message translates to:
  /// **'Toujours au premier plan'**
  String get alwaysOnTop;

  /// No description provided for @loading.
  ///
  /// In fr, this message translates to:
  /// **'Ouverture…'**
  String get loading;

  /// No description provided for @audioOnly.
  ///
  /// In fr, this message translates to:
  /// **'Audio'**
  String get audioOnly;

  /// No description provided for @speedValue.
  ///
  /// In fr, this message translates to:
  /// **'{speed}×'**
  String speedValue(String speed);

  /// No description provided for @resetSpeed.
  ///
  /// In fr, this message translates to:
  /// **'Vitesse normale'**
  String get resetSpeed;

  /// No description provided for @showRemainingTime.
  ///
  /// In fr, this message translates to:
  /// **'Afficher le temps restant'**
  String get showRemainingTime;

  /// No description provided for @showTotalTime.
  ///
  /// In fr, this message translates to:
  /// **'Afficher la durée totale'**
  String get showTotalTime;

  /// No description provided for @errorTitle.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de lire ce fichier'**
  String get errorTitle;

  /// No description provided for @errorFileNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Le fichier est introuvable. Il a peut-être été déplacé ou supprimé.'**
  String get errorFileNotFound;

  /// No description provided for @errorUnsupported.
  ///
  /// In fr, this message translates to:
  /// **'Ce type de fichier n\'est pas pris en charge par OMNIA.'**
  String get errorUnsupported;

  /// No description provided for @errorDecode.
  ///
  /// In fr, this message translates to:
  /// **'Le fichier semble endommagé, ou son format n\'est pas lisible par le moteur.'**
  String get errorDecode;

  /// No description provided for @errorPermission.
  ///
  /// In fr, this message translates to:
  /// **'OMNIA n\'a pas l\'autorisation de lire ce fichier ou ce dossier.'**
  String get errorPermission;

  /// No description provided for @errorEmptyFolder.
  ///
  /// In fr, this message translates to:
  /// **'Ce dossier ne contient aucun fichier qu\'OMNIA sache lire.'**
  String get errorEmptyFolder;

  /// No description provided for @errorUnknown.
  ///
  /// In fr, this message translates to:
  /// **'Une erreur inattendue s\'est produite pendant la lecture.'**
  String get errorUnknown;

  /// No description provided for @errorHint.
  ///
  /// In fr, this message translates to:
  /// **'Vous pouvez ouvrir un autre fichier, ou déposer un fichier ici.'**
  String get errorHint;

  /// No description provided for @openAnotherFile.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir un autre fichier'**
  String get openAnotherFile;

  /// No description provided for @panelShow.
  ///
  /// In fr, this message translates to:
  /// **'Afficher le panneau'**
  String get panelShow;

  /// No description provided for @panelHide.
  ///
  /// In fr, this message translates to:
  /// **'Masquer le panneau'**
  String get panelHide;

  /// No description provided for @panelSearchPlaceholder.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher dans le dossier'**
  String get panelSearchPlaceholder;

  /// No description provided for @panelScanning.
  ///
  /// In fr, this message translates to:
  /// **'Analyse du dossier…'**
  String get panelScanning;

  /// No description provided for @panelEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Aucun fichier lisible dans ce dossier'**
  String get panelEmpty;

  /// No description provided for @panelNoResults.
  ///
  /// In fr, this message translates to:
  /// **'Aucun résultat pour « {query} »'**
  String panelNoResults(String query);

  /// No description provided for @panelNoFolder.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrez un fichier pour voir ses voisins'**
  String get panelNoFolder;

  /// No description provided for @panelFileCount.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{aucun fichier} =1{1 fichier} other{{count} fichiers}}'**
  String panelFileCount(int count);

  /// No description provided for @panelFileCountFiltered.
  ///
  /// In fr, this message translates to:
  /// **'{visible} sur {total}'**
  String panelFileCountFiltered(int visible, int total);

  /// No description provided for @filterAll.
  ///
  /// In fr, this message translates to:
  /// **'Tous'**
  String get filterAll;

  /// No description provided for @filterVideo.
  ///
  /// In fr, this message translates to:
  /// **'Vidéo'**
  String get filterVideo;

  /// No description provided for @filterAudio.
  ///
  /// In fr, this message translates to:
  /// **'Audio'**
  String get filterAudio;

  /// No description provided for @filterDocuments.
  ///
  /// In fr, this message translates to:
  /// **'Documents'**
  String get filterDocuments;

  /// No description provided for @sortLabel.
  ///
  /// In fr, this message translates to:
  /// **'Trier'**
  String get sortLabel;

  /// No description provided for @sortName.
  ///
  /// In fr, this message translates to:
  /// **'Nom'**
  String get sortName;

  /// No description provided for @sortDate.
  ///
  /// In fr, this message translates to:
  /// **'Date'**
  String get sortDate;

  /// No description provided for @sortSize.
  ///
  /// In fr, this message translates to:
  /// **'Taille'**
  String get sortSize;

  /// No description provided for @sortType.
  ///
  /// In fr, this message translates to:
  /// **'Type'**
  String get sortType;

  /// No description provided for @sortAscending.
  ///
  /// In fr, this message translates to:
  /// **'Ordre croissant'**
  String get sortAscending;

  /// No description provided for @sortDescending.
  ///
  /// In fr, this message translates to:
  /// **'Ordre décroissant'**
  String get sortDescending;

  /// No description provided for @contextPlay.
  ///
  /// In fr, this message translates to:
  /// **'Lire'**
  String get contextPlay;

  /// No description provided for @contextRemove.
  ///
  /// In fr, this message translates to:
  /// **'Retirer de la liste'**
  String get contextRemove;

  /// No description provided for @contextReveal.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir l\'emplacement du fichier'**
  String get contextReveal;

  /// No description provided for @badgeWatched.
  ///
  /// In fr, this message translates to:
  /// **'Déjà lu'**
  String get badgeWatched;

  /// No description provided for @badgeResume.
  ///
  /// In fr, this message translates to:
  /// **'Reprendre à {time}'**
  String badgeResume(String time);

  /// No description provided for @nextFile.
  ///
  /// In fr, this message translates to:
  /// **'Fichier suivant'**
  String get nextFile;

  /// No description provided for @previousFile.
  ///
  /// In fr, this message translates to:
  /// **'Fichier précédent'**
  String get previousFile;

  /// No description provided for @endModeLabel.
  ///
  /// In fr, this message translates to:
  /// **'En fin de lecture'**
  String get endModeLabel;

  /// No description provided for @endModeStop.
  ///
  /// In fr, this message translates to:
  /// **'S\'arrêter'**
  String get endModeStop;

  /// No description provided for @endModeNext.
  ///
  /// In fr, this message translates to:
  /// **'Fichier suivant'**
  String get endModeNext;

  /// No description provided for @endModeRepeatOne.
  ///
  /// In fr, this message translates to:
  /// **'Répéter le fichier'**
  String get endModeRepeatOne;

  /// No description provided for @endModeLoopFolder.
  ///
  /// In fr, this message translates to:
  /// **'Boucler le dossier'**
  String get endModeLoopFolder;

  /// No description provided for @endModeShuffle.
  ///
  /// In fr, this message translates to:
  /// **'Lecture aléatoire'**
  String get endModeShuffle;

  /// No description provided for @clearSearch.
  ///
  /// In fr, this message translates to:
  /// **'Effacer la recherche'**
  String get clearSearch;

  /// No description provided for @resizePanel.
  ///
  /// In fr, this message translates to:
  /// **'Redimensionner le panneau'**
  String get resizePanel;

  /// No description provided for @osdMuted.
  ///
  /// In fr, this message translates to:
  /// **'Muet'**
  String get osdMuted;

  /// No description provided for @osdVolume.
  ///
  /// In fr, this message translates to:
  /// **'{volume}'**
  String osdVolume(int volume);

  /// No description provided for @osdAlwaysOnTopOn.
  ///
  /// In fr, this message translates to:
  /// **'Toujours au premier plan'**
  String get osdAlwaysOnTopOn;

  /// No description provided for @osdAlwaysOnTopOff.
  ///
  /// In fr, this message translates to:
  /// **'Premier plan désactivé'**
  String get osdAlwaysOnTopOff;

  /// No description provided for @menuSpeed.
  ///
  /// In fr, this message translates to:
  /// **'Vitesse'**
  String get menuSpeed;

  /// No description provided for @recentFiles.
  ///
  /// In fr, this message translates to:
  /// **'Fichiers récents'**
  String get recentFiles;

  /// No description provided for @clearRecent.
  ///
  /// In fr, this message translates to:
  /// **'Effacer les récents'**
  String get clearRecent;

  /// No description provided for @noRecentFiles.
  ///
  /// In fr, this message translates to:
  /// **'Aucun fichier récent'**
  String get noRecentFiles;

  /// No description provided for @recentMissing.
  ///
  /// In fr, this message translates to:
  /// **'Fichier introuvable'**
  String get recentMissing;

  /// No description provided for @helpTitle.
  ///
  /// In fr, this message translates to:
  /// **'Raccourcis clavier'**
  String get helpTitle;

  /// No description provided for @helpClose.
  ///
  /// In fr, this message translates to:
  /// **'Fermer l\'aide'**
  String get helpClose;

  /// No description provided for @helpSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Tout se pilote au clavier. Ces raccourcis seront personnalisables dans les paramètres.'**
  String get helpSubtitle;

  /// No description provided for @helpGroupPlayback.
  ///
  /// In fr, this message translates to:
  /// **'Lecture'**
  String get helpGroupPlayback;

  /// No description provided for @helpGroupNavigation.
  ///
  /// In fr, this message translates to:
  /// **'Navigation'**
  String get helpGroupNavigation;

  /// No description provided for @helpGroupWindow.
  ///
  /// In fr, this message translates to:
  /// **'Fenêtre'**
  String get helpGroupWindow;

  /// No description provided for @helpPlayPause.
  ///
  /// In fr, this message translates to:
  /// **'Lecture / pause'**
  String get helpPlayPause;

  /// No description provided for @helpSeekShort.
  ///
  /// In fr, this message translates to:
  /// **'Reculer / avancer de 5 s'**
  String get helpSeekShort;

  /// No description provided for @helpSeekMedium.
  ///
  /// In fr, this message translates to:
  /// **'Reculer / avancer de 30 s'**
  String get helpSeekMedium;

  /// No description provided for @helpSeekLong.
  ///
  /// In fr, this message translates to:
  /// **'Reculer / avancer de 60 s'**
  String get helpSeekLong;

  /// No description provided for @helpVolume.
  ///
  /// In fr, this message translates to:
  /// **'Volume + / −'**
  String get helpVolume;

  /// No description provided for @helpSpeed.
  ///
  /// In fr, this message translates to:
  /// **'Vitesse + / −'**
  String get helpSpeed;

  /// No description provided for @helpPanelToggle.
  ///
  /// In fr, this message translates to:
  /// **'Afficher / masquer le panneau'**
  String get helpPanelToggle;

  /// No description provided for @helpLeaveSearch.
  ///
  /// In fr, this message translates to:
  /// **'Quitter la recherche'**
  String get helpLeaveSearch;

  /// No description provided for @errorProtectedDocument.
  ///
  /// In fr, this message translates to:
  /// **'Ce document est protégé par un mot de passe. OMNIA ne peut pas l\'ouvrir.'**
  String get errorProtectedDocument;

  /// No description provided for @docPageLabel.
  ///
  /// In fr, this message translates to:
  /// **'Page'**
  String get docPageLabel;

  /// No description provided for @docPageOf.
  ///
  /// In fr, this message translates to:
  /// **'{page} / {total}'**
  String docPageOf(int page, int total);

  /// No description provided for @docGoToPage.
  ///
  /// In fr, this message translates to:
  /// **'Aller à la page'**
  String get docGoToPage;

  /// No description provided for @docPreviousPage.
  ///
  /// In fr, this message translates to:
  /// **'Page précédente'**
  String get docPreviousPage;

  /// No description provided for @docNextPage.
  ///
  /// In fr, this message translates to:
  /// **'Page suivante'**
  String get docNextPage;

  /// No description provided for @docZoomIn.
  ///
  /// In fr, this message translates to:
  /// **'Agrandir'**
  String get docZoomIn;

  /// No description provided for @docZoomOut.
  ///
  /// In fr, this message translates to:
  /// **'Réduire'**
  String get docZoomOut;

  /// No description provided for @docZoomValue.
  ///
  /// In fr, this message translates to:
  /// **'{percent} %'**
  String docZoomValue(int percent);

  /// No description provided for @docFitWidth.
  ///
  /// In fr, this message translates to:
  /// **'Ajuster à la largeur'**
  String get docFitWidth;

  /// No description provided for @docFitPage.
  ///
  /// In fr, this message translates to:
  /// **'Ajuster à la page'**
  String get docFitPage;

  /// No description provided for @docRotate.
  ///
  /// In fr, this message translates to:
  /// **'Pivoter de 90°'**
  String get docRotate;

  /// No description provided for @docReadingDark.
  ///
  /// In fr, this message translates to:
  /// **'Mode sombre de lecture'**
  String get docReadingDark;

  /// No description provided for @docLayoutContinuous.
  ///
  /// In fr, this message translates to:
  /// **'Défilement continu'**
  String get docLayoutContinuous;

  /// No description provided for @docLayoutPaged.
  ///
  /// In fr, this message translates to:
  /// **'Page par page'**
  String get docLayoutPaged;

  /// No description provided for @docFind.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher'**
  String get docFind;

  /// No description provided for @docFontSize.
  ///
  /// In fr, this message translates to:
  /// **'Taille du texte'**
  String get docFontSize;

  /// No description provided for @docEncoding.
  ///
  /// In fr, this message translates to:
  /// **'Encodage : {encoding}'**
  String docEncoding(String encoding);

  /// No description provided for @docLines.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{aucune ligne} =1{1 ligne} other{{count} lignes}}'**
  String docLines(int count);

  /// No description provided for @findPlaceholder.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher dans le document'**
  String get findPlaceholder;

  /// No description provided for @findMatches.
  ///
  /// In fr, this message translates to:
  /// **'{index} / {count}'**
  String findMatches(int index, int count);

  /// No description provided for @findNoMatch.
  ///
  /// In fr, this message translates to:
  /// **'Aucun résultat'**
  String get findNoMatch;

  /// No description provided for @findNext.
  ///
  /// In fr, this message translates to:
  /// **'Résultat suivant'**
  String get findNext;

  /// No description provided for @findPrevious.
  ///
  /// In fr, this message translates to:
  /// **'Résultat précédent'**
  String get findPrevious;

  /// No description provided for @findClose.
  ///
  /// In fr, this message translates to:
  /// **'Fermer la recherche'**
  String get findClose;

  /// No description provided for @panelTabFolder.
  ///
  /// In fr, this message translates to:
  /// **'Dossier'**
  String get panelTabFolder;

  /// No description provided for @panelTabOutline.
  ///
  /// In fr, this message translates to:
  /// **'Sommaire'**
  String get panelTabOutline;

  /// No description provided for @panelTabPages.
  ///
  /// In fr, this message translates to:
  /// **'Pages'**
  String get panelTabPages;

  /// No description provided for @docNoOutline.
  ///
  /// In fr, this message translates to:
  /// **'Ce document n\'a pas de sommaire'**
  String get docNoOutline;

  /// No description provided for @docLoading.
  ///
  /// In fr, this message translates to:
  /// **'Chargement du document…'**
  String get docLoading;

  /// No description provided for @helpGroupDocuments.
  ///
  /// In fr, this message translates to:
  /// **'Documents'**
  String get helpGroupDocuments;

  /// No description provided for @subtitles.
  ///
  /// In fr, this message translates to:
  /// **'Sous-titres'**
  String get subtitles;

  /// No description provided for @subtitlesOff.
  ///
  /// In fr, this message translates to:
  /// **'Sous-titres désactivés'**
  String get subtitlesOff;

  /// No description provided for @subtitlesNone.
  ///
  /// In fr, this message translates to:
  /// **'Aucun'**
  String get subtitlesNone;

  /// No description provided for @subtitlesLoadFile.
  ///
  /// In fr, this message translates to:
  /// **'Charger un fichier de sous-titres…'**
  String get subtitlesLoadFile;

  /// No description provided for @subtitleDelay.
  ///
  /// In fr, this message translates to:
  /// **'Décalage'**
  String get subtitleDelay;

  /// No description provided for @subtitleDelayValue.
  ///
  /// In fr, this message translates to:
  /// **'{seconds} s'**
  String subtitleDelayValue(String seconds);

  /// No description provided for @subtitleSize.
  ///
  /// In fr, this message translates to:
  /// **'Taille des sous-titres'**
  String get subtitleSize;

  /// No description provided for @audioTracks.
  ///
  /// In fr, this message translates to:
  /// **'Piste audio'**
  String get audioTracks;

  /// No description provided for @audioTrackAuto.
  ///
  /// In fr, this message translates to:
  /// **'Automatique'**
  String get audioTrackAuto;

  /// No description provided for @noTracks.
  ///
  /// In fr, this message translates to:
  /// **'Aucune piste'**
  String get noTracks;

  /// No description provided for @abLoop.
  ///
  /// In fr, this message translates to:
  /// **'Boucle A-B'**
  String get abLoop;

  /// No description provided for @abLoopSetA.
  ///
  /// In fr, this message translates to:
  /// **'Point A posé'**
  String get abLoopSetA;

  /// No description provided for @abLoopSetB.
  ///
  /// In fr, this message translates to:
  /// **'Boucle A-B active'**
  String get abLoopSetB;

  /// No description provided for @abLoopCleared.
  ///
  /// In fr, this message translates to:
  /// **'Boucle A-B désactivée'**
  String get abLoopCleared;

  /// No description provided for @screenshot.
  ///
  /// In fr, this message translates to:
  /// **'Capture d\'écran'**
  String get screenshot;

  /// No description provided for @screenshotSaved.
  ///
  /// In fr, this message translates to:
  /// **'Capture enregistrée'**
  String get screenshotSaved;

  /// No description provided for @image.
  ///
  /// In fr, this message translates to:
  /// **'Image'**
  String get image;

  /// No description provided for @aspectRatio.
  ///
  /// In fr, this message translates to:
  /// **'Ratio d\'aspect'**
  String get aspectRatio;

  /// No description provided for @aspectAuto.
  ///
  /// In fr, this message translates to:
  /// **'Automatique'**
  String get aspectAuto;

  /// No description provided for @aspectWide.
  ///
  /// In fr, this message translates to:
  /// **'16:9'**
  String get aspectWide;

  /// No description provided for @aspectStandard.
  ///
  /// In fr, this message translates to:
  /// **'4:3'**
  String get aspectStandard;

  /// No description provided for @aspectFill.
  ///
  /// In fr, this message translates to:
  /// **'Remplir'**
  String get aspectFill;

  /// No description provided for @videoZoom.
  ///
  /// In fr, this message translates to:
  /// **'Zoom vidéo'**
  String get videoZoom;

  /// No description provided for @videoZoomValue.
  ///
  /// In fr, this message translates to:
  /// **'Zoom {percent} %'**
  String videoZoomValue(int percent);

  /// No description provided for @videoZoomReset.
  ///
  /// In fr, this message translates to:
  /// **'Zoom normal'**
  String get videoZoomReset;

  /// No description provided for @videoRotate.
  ///
  /// In fr, this message translates to:
  /// **'Pivoter la vidéo'**
  String get videoRotate;

  /// No description provided for @videoRotation.
  ///
  /// In fr, this message translates to:
  /// **'Rotation {degrees}°'**
  String videoRotation(int degrees);

  /// No description provided for @imageAdjust.
  ///
  /// In fr, this message translates to:
  /// **'Réglages d\'image…'**
  String get imageAdjust;

  /// No description provided for @brightness.
  ///
  /// In fr, this message translates to:
  /// **'Luminosité'**
  String get brightness;

  /// No description provided for @contrast.
  ///
  /// In fr, this message translates to:
  /// **'Contraste'**
  String get contrast;

  /// No description provided for @saturation.
  ///
  /// In fr, this message translates to:
  /// **'Saturation'**
  String get saturation;

  /// No description provided for @resetAdjust.
  ///
  /// In fr, this message translates to:
  /// **'Réinitialiser'**
  String get resetAdjust;

  /// No description provided for @equalizer.
  ///
  /// In fr, this message translates to:
  /// **'Égaliseur'**
  String get equalizer;

  /// No description provided for @equalizerOn.
  ///
  /// In fr, this message translates to:
  /// **'Égaliseur activé'**
  String get equalizerOn;

  /// No description provided for @equalizerOff.
  ///
  /// In fr, this message translates to:
  /// **'Égaliseur désactivé'**
  String get equalizerOff;

  /// No description provided for @equalizerPreset.
  ///
  /// In fr, this message translates to:
  /// **'Préréglage'**
  String get equalizerPreset;

  /// No description provided for @presetNormal.
  ///
  /// In fr, this message translates to:
  /// **'Normal'**
  String get presetNormal;

  /// No description provided for @presetRock.
  ///
  /// In fr, this message translates to:
  /// **'Rock'**
  String get presetRock;

  /// No description provided for @presetPop.
  ///
  /// In fr, this message translates to:
  /// **'Pop'**
  String get presetPop;

  /// No description provided for @presetJazz.
  ///
  /// In fr, this message translates to:
  /// **'Jazz'**
  String get presetJazz;

  /// No description provided for @presetClassical.
  ///
  /// In fr, this message translates to:
  /// **'Classique'**
  String get presetClassical;

  /// No description provided for @presetBass.
  ///
  /// In fr, this message translates to:
  /// **'Basses'**
  String get presetBass;

  /// No description provided for @presetTreble.
  ///
  /// In fr, this message translates to:
  /// **'Aigus'**
  String get presetTreble;

  /// No description provided for @presetVocal.
  ///
  /// In fr, this message translates to:
  /// **'Vocal'**
  String get presetVocal;

  /// No description provided for @presetElectronic.
  ///
  /// In fr, this message translates to:
  /// **'Électro'**
  String get presetElectronic;

  /// No description provided for @presetAcoustic.
  ///
  /// In fr, this message translates to:
  /// **'Acoustique'**
  String get presetAcoustic;

  /// No description provided for @presetCustom.
  ///
  /// In fr, this message translates to:
  /// **'Personnalisé'**
  String get presetCustom;

  /// No description provided for @miniPlayer.
  ///
  /// In fr, this message translates to:
  /// **'Mini-lecteur'**
  String get miniPlayer;

  /// No description provided for @miniPlayerExit.
  ///
  /// In fr, this message translates to:
  /// **'Quitter le mini-lecteur'**
  String get miniPlayerExit;

  /// No description provided for @unknownArtist.
  ///
  /// In fr, this message translates to:
  /// **'Artiste inconnu'**
  String get unknownArtist;

  /// No description provided for @closePanel.
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get closePanel;

  /// No description provided for @screenshotFailed.
  ///
  /// In fr, this message translates to:
  /// **'Capture impossible'**
  String get screenshotFailed;

  /// No description provided for @screenshotFailedHint.
  ///
  /// In fr, this message translates to:
  /// **'Le dossier des captures est inaccessible. Choisissez-en un autre dans les paramètres.'**
  String get screenshotFailedHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
