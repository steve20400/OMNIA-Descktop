; Installateur Windows d'OMNIA (Inno Setup 6).
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
; Mise à niveau en place transparente sans désinstallation préalable :
; Réutilise automatiquement le dossier, les groupes et les préférences de la version existante.
UsePreviousAppDir=yes
UsePreviousGroup=yes
UsePreviousTasks=yes
UsePreviousPrivileges=yes
CloseApplications=yes
CloseApplicationsFilter=omnia.exe
RestartApplications=yes

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
Root: HKA; Subkey: "Software\Classes\.docx\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".docx"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.doc\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".doc"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.odt\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".odt"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.rtf\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".rtf"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.dotx\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".dotx"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.docm\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".docm"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.dotm\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".dotm"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.fodt\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".fodt"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ott\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ott"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.pptx\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".pptx"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ppt\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ppt"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ppsx\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ppsx"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.odp\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".odp"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.fodp\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".fodp"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.otp\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".otp"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.txt\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".txt"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.md\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".md"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.markdown\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".markdown"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.log\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".log"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.json\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".json"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.yaml\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".yaml"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.yml\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".yml"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.xml\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".xml"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.csv\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".csv"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.tsv\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".tsv"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ini\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ini"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.conf\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".conf"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.cfg\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".cfg"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.properties\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".properties"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.toml\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".toml"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.srt\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".srt"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.vtt\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".vtt"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.sub\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".sub"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ass\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ass"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.lrc\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".lrc"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.sql\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".sql"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.sh\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".sh"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.bash\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".bash"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.bat\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".bat"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.cmd\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".cmd"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ps1\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ps1"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.html\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".html"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.htm\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".htm"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.css\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".css"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.js\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".js"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.dart\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".dart"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.py\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".py"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.c\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".c"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.cpp\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".cpp"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.h\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".h"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.hpp\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".hpp"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.java\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".java"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.rs\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".rs"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.go\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".go"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.aux\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".aux"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.tex\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".tex"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.latex\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".latex"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.bib\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".bib"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.cls\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".cls"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.sty\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".sty"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.toc\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".toc"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.lof\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".lof"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.lot\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".lot"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.bbl\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".bbl"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.blg\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".blg"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.idx\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".idx"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ilg\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ilg"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ind\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ind"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.out\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".out"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.diff\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".diff"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.patch\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".patch"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.env\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".env"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.reg\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".reg"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.inf\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".inf"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.lock\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Document"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".lock"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.png\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Image"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".png"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.jpg\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Image"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".jpg"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.jpeg\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Image"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".jpeg"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.webp\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Image"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".webp"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.gif\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Image"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".gif"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.bmp\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Image"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".bmp"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.ico\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Image"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".ico"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.svg\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Image"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".svg"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.avif\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Image"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".avif"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.tif\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Image"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".tif"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.tiff\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Image"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".tiff"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.heic\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Image"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".heic"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.heif\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Image"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".heif"; ValueData: ""; Tasks: associate
Root: HKA; Subkey: "Software\Classes\.jfif\OpenWithProgids"; ValueType: none; ValueName: "OMNIA.Image"; Flags: uninsdeletevalue; Tasks: associate
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".jfif"; ValueData: ""; Tasks: associate
; END EXTENSIONS

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
