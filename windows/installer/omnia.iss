﻿; Installateur Windows d'OMNIA (Inno Setup 6).
;
; 1. flutter build windows --release
; 2. iscc windows\installer\omnia.iss
;    → build\installer\OMNIA-Setup-<version>.exe
;
; Les associations de fichiers inscrivent OMNIA dans « Ouvrir avec » pour
; chaque format lisible, sans détourner l'application par défaut : Windows 10
; et 11 laissent ce choix à l'utilisateur (Paramètres > Applications par
; défaut). La liste des extensions est générée depuis MediaRouter par
; tool/make_installer_assoc.py : ne pas la modifier à la main.

#define AppName "OMNIA"
; La CI transmet la version du pubspec : iscc /DAppVersion=0.1.0 omnia.iss
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#define AppPublisher "OMNIA"
#define AppExe "omnia.exe"
#define BuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{8E1F3C52-6B7A-4D3E-9F21-0A5C7D4B9E60}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\..\build\installer
OutputBaseFilename=OMNIA-Setup-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Installation pour tous (administrateur) ou pour soi seul, au choix.
PrivilegesRequiredOverridesAllowed=dialog
ChangesAssociations=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
french.AssocGroup=Associations de fichiers :
english.AssocGroup=File associations:
french.AssocTask=Proposer OMNIA dans « Ouvrir avec » pour les vidéos, musiques, PDF et textes
english.AssocTask=Offer OMNIA in “Open with” for videos, music, PDFs and text files
french.VideoType=Vidéo (OMNIA)
english.VideoType=Video (OMNIA)
french.AudioType=Audio (OMNIA)
english.AudioType=Audio (OMNIA)
french.DocumentType=Document (OMNIA)
english.DocumentType=Document (OMNIA)

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "associate"; Description: "{cm:AssocTask}"; GroupDescription: "{cm:AssocGroup}"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; Application : nom affiché et commande d'ouverture (« Ouvrir avec »).
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "{#AppName}"; Flags: uninsdeletekey; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExe},0"; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: associate

; Types de fichiers d'OMNIA (ProgId), un par famille.
Root: HKA; Subkey: "Software\Classes\OMNIA.Video"; ValueType: string; ValueName: ""; ValueData: "{cm:VideoType}"; Flags: uninsdeletekey; Tasks: associate
Root: HKA; Subkey: "Software\Classes\OMNIA.Video\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExe},0"; Tasks: associate
Root: HKA; Subkey: "Software\Classes\OMNIA.Video\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\OMNIA.Audio"; ValueType: string; ValueName: ""; ValueData: "{cm:AudioType}"; Flags: uninsdeletekey; Tasks: associate
Root: HKA; Subkey: "Software\Classes\OMNIA.Audio\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExe},0"; Tasks: associate
Root: HKA; Subkey: "Software\Classes\OMNIA.Audio\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\OMNIA.Document"; ValueType: string; ValueName: ""; ValueData: "{cm:DocumentType}"; Flags: uninsdeletekey; Tasks: associate
Root: HKA; Subkey: "Software\Classes\OMNIA.Document\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExe},0"; Tasks: associate
Root: HKA; Subkey: "Software\Classes\OMNIA.Document\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: associate

; BEGIN EXTENSIONS
; Généré par tool/make_installer_assoc.py — ne pas modifier à la main.
Root: HKA; Subkey: "Software\Classes\.mp4\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mp4"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.m4v\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".m4v"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.mkv\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mkv"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.mk3d\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mk3d"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.webm\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".webm"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.avi\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".avi"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.mov\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mov"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.qt\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".qt"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.wmv\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".wmv"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.asf\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".asf"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.flv\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".flv"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.f4v\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".f4v"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ogv\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ogv"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ogm\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ogm"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.3gp\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".3gp"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.3g2\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".3g2"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.divx\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".divx"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.xvid\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".xvid"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.mpg\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mpg"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.mpeg\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mpeg"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.mpe\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mpe"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.mpv\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mpv"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.m1v\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".m1v"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.m2v\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".m2v"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.m2p\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".m2p"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.vob\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".vob"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.evo\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".evo"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ts\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ts"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.m2ts\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".m2ts"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.mts\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mts"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.m2t\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".m2t"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.tp\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".tp"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.trp\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".trp"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.tod\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".tod"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.wtv\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".wtv"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.h264\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".h264"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.h265\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".h265"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.hevc\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".hevc"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.264\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".264"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.265\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".265"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ivf\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ivf"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.y4m\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".y4m"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.dv\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".dv"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.mxf\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mxf"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.nut\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".nut"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.gxf\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".gxf"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.rm\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".rm"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.rmvb\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".rmvb"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.amv\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".amv"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.bik\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Video"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".bik"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.mp3\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mp3"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.aac\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".aac"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.m4a\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".m4a"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.m4b\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".m4b"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.m4r\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".m4r"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.flac\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".flac"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.wav\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".wav"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.wave\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".wave"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ogg\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ogg"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.oga\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".oga"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.opus\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".opus"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.wma\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".wma"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.weba\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".weba"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.aiff\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".aiff"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.aif\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".aif"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.aifc\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".aifc"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ape\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ape"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.wv\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".wv"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.tta\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".tta"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.tak\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".tak"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.w64\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".w64"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.dsf\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".dsf"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.dff\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".dff"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.caf\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".caf"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.shn\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".shn"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ofr\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ofr"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ac3\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ac3"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.eac3\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".eac3"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ec3\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ec3"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.dts\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".dts"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.dtshd\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".dtshd"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.mlp\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mlp"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.thd\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".thd"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.truehd\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".truehd"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.mka\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mka"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.mp2\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mp2"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.mp1\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mp1"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.mpa\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mpa"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.adts\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".adts"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.amr\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".amr"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.awb\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".awb"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.spx\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".spx"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.gsm\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".gsm"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.au\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".au"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.snd\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".snd"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.voc\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".voc"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ra\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ra"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.mpc\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".mpc"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.oma\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Audio"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".oma"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.pdf\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".pdf"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.txt\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".txt"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.md\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".md"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.markdown\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".markdown"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.log\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".log"; ValueData: ""; Tasks: associate
; END EXTENSIONS

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
