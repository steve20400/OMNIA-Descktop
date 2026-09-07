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
  String get errorUnknown => 'An unexpected error occurred during playback.';

  @override
  String get errorHint => 'You can open another file, or drop one here.';

  @override
  String get openAnotherFile => 'Open another file';

  @override
  String shortcutHint(String shortcut) {
    return '$shortcut';
  }
}
