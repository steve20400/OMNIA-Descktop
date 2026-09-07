// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'OMNIA';

  @override
  String get emptyStageHint => 'Drop a file or a folder here';

  @override
  String get emptyStageSubtitle =>
      'Video, audio, PDF and text — everything plays here.';

  @override
  String get openFile => 'Open a file';

  @override
  String get openFolder => 'Open a folder';

  @override
  String get dropToPlay => 'Drop to play';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get mute => 'Mute';

  @override
  String get unmute => 'Unmute';

  @override
  String get fullscreen => 'Fullscreen';

  @override
  String get exitFullscreen => 'Exit fullscreen';

  @override
  String get minimize => 'Minimize';

  @override
  String get maximize => 'Maximize';

  @override
  String get restore => 'Restore';

  @override
  String get closeWindow => 'Close';

  @override
  String get alwaysOnTop => 'Always on top';

  @override
  String get loading => 'Opening…';

  @override
  String get audioOnly => 'Audio';

  @override
  String speedValue(String speed) {
    return '$speed×';
  }

  @override
  String get resetSpeed => 'Normal speed';

  @override
  String get showRemainingTime => 'Show remaining time';

  @override
  String get showTotalTime => 'Show total duration';

  @override
  String get errorTitle => 'This file cannot be played';

  @override
  String get errorFileNotFound =>
      'The file cannot be found. It may have been moved or deleted.';

  @override
  String get errorUnsupported => 'This file type is not supported by OMNIA.';

  @override
  String get errorDecode =>
      'The file looks damaged, or its format cannot be decoded by the engine.';

  @override
  String get errorPermission =>
      'OMNIA is not allowed to read this file or folder.';

  @override
  String get errorEmptyFolder => 'This folder holds no file OMNIA can read.';

  @override
  String get errorUnknown => 'An unexpected error occurred during playback.';

  @override
  String get errorHint => 'You can open another file, or drop one here.';

  @override
  String get openAnotherFile => 'Open another file';

  @override
  String get panelShow => 'Show panel';

  @override
  String get panelHide => 'Hide panel';

  @override
  String get panelSearchPlaceholder => 'Search this folder';

  @override
  String get panelScanning => 'Scanning folder…';

  @override
  String get panelEmpty => 'No readable file in this folder';

  @override
  String panelNoResults(String query) {
    return 'No result for “$query”';
  }

  @override
  String get panelNoFolder => 'Open a file to see its neighbours';

  @override
  String panelFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
      zero: 'no file',
    );
    return '$_temp0';
  }

  @override
  String panelFileCountFiltered(int visible, int total) {
    return '$visible of $total';
  }

  @override
  String get filterAll => 'All';

  @override
  String get filterVideo => 'Video';

  @override
  String get filterAudio => 'Audio';

  @override
  String get filterDocuments => 'Documents';

  @override
  String get sortLabel => 'Sort';

  @override
  String get sortName => 'Name';

  @override
  String get sortDate => 'Date';

  @override
  String get sortSize => 'Size';

  @override
  String get sortType => 'Type';

  @override
  String get sortAscending => 'Ascending';

  @override
  String get sortDescending => 'Descending';

  @override
  String get contextPlay => 'Play';

  @override
  String get contextRemove => 'Remove from list';

  @override
  String get contextReveal => 'Open file location';

  @override
  String get badgeWatched => 'Watched';

  @override
  String badgeResume(String time) {
    return 'Resume at $time';
  }

  @override
  String get nextFile => 'Next file';

  @override
  String get previousFile => 'Previous file';

  @override
  String get endModeLabel => 'When playback ends';

  @override
  String get endModeStop => 'Stop';

  @override
  String get endModeNext => 'Next file';

  @override
  String get endModeRepeatOne => 'Repeat file';

  @override
  String get endModeLoopFolder => 'Loop folder';

  @override
  String get endModeShuffle => 'Shuffle';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get resizePanel => 'Resize panel';
}
