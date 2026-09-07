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
