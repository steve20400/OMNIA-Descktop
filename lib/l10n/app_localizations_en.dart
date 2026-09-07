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

  @override
  String get osdMuted => 'Muted';

  @override
  String osdVolume(int volume) {
    return '$volume';
  }

  @override
  String get osdAlwaysOnTopOn => 'Always on top';

  @override
  String get osdAlwaysOnTopOff => 'Always on top off';

  @override
  String get menuSpeed => 'Speed';

  @override
  String get recentFiles => 'Recent files';

  @override
  String get clearRecent => 'Clear recent files';

  @override
  String get noRecentFiles => 'No recent file';

  @override
  String get recentMissing => 'File not found';

  @override
  String get helpTitle => 'Keyboard shortcuts';

  @override
  String get helpClose => 'Close help';

  @override
  String get helpSubtitle =>
      'Everything can be driven from the keyboard. These shortcuts will be customisable in Settings.';

  @override
  String get helpGroupPlayback => 'Playback';

  @override
  String get helpGroupNavigation => 'Navigation';

  @override
  String get helpGroupWindow => 'Window';

  @override
  String get helpPlayPause => 'Play / pause';

  @override
  String get helpSeekShort => 'Back / forward 5 s';

  @override
  String get helpSeekMedium => 'Back / forward 30 s';

  @override
  String get helpSeekLong => 'Back / forward 60 s';

  @override
  String get helpVolume => 'Volume up / down';

  @override
  String get helpSpeed => 'Speed up / down';

  @override
  String get helpPanelToggle => 'Show / hide the panel';

  @override
  String get helpLeaveSearch => 'Leave the search field';

  @override
  String get errorProtectedDocument =>
      'This document is password-protected. OMNIA cannot open it.';

  @override
  String get docPageLabel => 'Page';

  @override
  String docPageOf(int page, int total) {
    return '$page / $total';
  }

  @override
  String get docGoToPage => 'Go to page';

  @override
  String get docPreviousPage => 'Previous page';

  @override
  String get docNextPage => 'Next page';

  @override
  String get docZoomIn => 'Zoom in';

  @override
  String get docZoomOut => 'Zoom out';

  @override
  String docZoomValue(int percent) {
    return '$percent %';
  }

  @override
  String get docFitWidth => 'Fit width';

  @override
  String get docFitPage => 'Fit page';

  @override
  String get docRotate => 'Rotate 90°';

  @override
  String get docReadingDark => 'Reading dark mode';

  @override
  String get docLayoutContinuous => 'Continuous scrolling';

  @override
  String get docLayoutPaged => 'Page by page';

  @override
  String get docFind => 'Find';

  @override
  String get docFontSize => 'Text size';

  @override
  String docEncoding(String encoding) {
    return 'Encoding: $encoding';
  }

  @override
  String docLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines',
      one: '1 line',
      zero: 'no line',
    );
    return '$_temp0';
  }

  @override
  String get findPlaceholder => 'Find in document';

  @override
  String findMatches(int index, int count) {
    return '$index / $count';
  }

  @override
  String get findNoMatch => 'No match';

  @override
  String get findNext => 'Next match';

  @override
  String get findPrevious => 'Previous match';

  @override
  String get findClose => 'Close find';

  @override
  String get panelTabFolder => 'Folder';

  @override
  String get panelTabOutline => 'Outline';

  @override
  String get panelTabPages => 'Pages';

  @override
  String get docNoOutline => 'This document has no outline';

  @override
  String get docLoading => 'Loading document…';

  @override
  String get helpGroupDocuments => 'Documents';
}
