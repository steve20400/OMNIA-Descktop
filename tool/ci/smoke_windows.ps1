# Lancement réel d'OMNIA sur la machine Windows de la CI.
#
# 0. Le dossier Release contient les bibliothèques natives : moteur Flutter,
#    code de l'application, libmpv, pdfium.
# 1. OMNIA démarre avec un son en argument, comme par « Ouvrir avec », et doit
#    rester ouvert : libmpv, la fenêtre et le stockage local se sont initialisés.
# 2. Une seconde instance reçoit un PDF, comme un fichier déposé sur l'icône :
#    elle doit le confier à la première fenêtre et se terminer aussitôt.
# 3. Après fermeture, l'historique prouve que libmpv a ouvert le son et que
#    pdfium a ouvert le PDF (voir le détail à l'étape 3).
#
# Une capture d'écran est prise à chaque étape, dans -OutDir.
#
# Usage : ./tool/ci/smoke_windows.ps1 -Exe <omnia.exe> -OutDir <dossier>
param(
  [Parameter(Mandatory = $true)] [string] $Exe,
  [Parameter(Mandatory = $true)] [string] $OutDir
)

$ErrorActionPreference = 'Stop'
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path

$samples = Join-Path $env:RUNNER_TEMP 'omnia-essai'
python tool/ci/make_samples.py $samples
if ($LASTEXITCODE -ne 0) { throw 'Fichiers d''essai non générés.' }
$wav = Join-Path $samples 'Musique\essai.wav'
$pdf = Join-Path $samples 'Documents\essai.pdf'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Save-Screen([string] $name) {
  try {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $bitmap.Save((Join-Path $OutDir $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
  } catch {
    Write-Output "::warning title=Capture d'écran::$name non capturée : $($_.Exception.Message)"
  }
}

# Fin d'un journal, bornée puis encodée : GitHub ne garde que les 4096
# premiers caractères d'une annotation, et c'est la fin qui compte.
function Get-LogTail([string] $path) {
  if (-not (Test-Path $path)) { return '' }
  $text = (Get-Content -Path $path -Tail 30 -ErrorAction SilentlyContinue) -join "`n"
  if ($text.Length -gt 3000) { $text = $text.Substring($text.Length - 3000) }
  return ($text -replace '%', '%25' -replace "`r", '' -replace "`n", '%0A')
}

# [logName] : journal joint au message, celui de l'instance en cause.
function Fail([string] $message, [string] $logName = 'omnia-stderr.txt') {
  $tail = Get-LogTail (Join-Path $OutDir $logName)
  if ($tail) { $message = "$message%0A%0ASortie d'erreur ($logName) :%0A$tail" }
  Write-Output "::error title=Lancement réel (Windows)::$message"
  Get-Process -Name omnia -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  exit 1
}

function Start-Omnia([string] $file, [string] $logName) {
  $process = Start-Process -FilePath $Exe -ArgumentList ('"{0}"' -f $file) -PassThru `
    -RedirectStandardOutput (Join-Path $OutDir "$logName-stdout.txt") `
    -RedirectStandardError (Join-Path $OutDir "$logName-stderr.txt")
  # Sans cette lecture, ExitCode reste vide une fois le processus terminé.
  $null = $process.Handle
  return $process
}

# 0. Bibliothèques natives présentes à côté de l'exécutable.
$release = Split-Path -Parent $Exe
foreach ($pattern in @('flutter_windows.dll', 'app.so', 'libmpv*.dll', 'pdfium*.dll')) {
  if (-not (Get-ChildItem -Path $release -Recurse -Filter $pattern -ErrorAction SilentlyContinue)) {
    Fail "$pattern est absent du dossier Release : l'application ne pourrait pas s'en servir."
  }
}

# 1. Première instance, avec le son.
$first = Start-Omnia $wav 'omnia'
Start-Sleep -Seconds 20
Save-Screen '1-lecture-audio.png'
if ($first.HasExited) { Fail "OMNIA s'est arrêté au démarrage (code $($first.ExitCode))." }

# 2. Seconde instance, avec le PDF : elle doit déléguer et se retirer.
$second = Start-Omnia $pdf 'seconde-instance'
if (-not $second.WaitForExit(30000)) {
  Save-Screen '2-seconde-instance.png'
  Fail 'La seconde instance est restée ouverte : le PDF n''a pas été confié à la première fenêtre.' 'seconde-instance-stderr.txt'
}
if ($second.ExitCode -ne 0) {
  Fail "La seconde instance s'est terminée en erreur (code $($second.ExitCode))." 'seconde-instance-stderr.txt'
}
Start-Sleep -Seconds 10
Save-Screen '2-document-pdf.png'
if ($first.HasExited) { Fail "OMNIA s'est arrêté après avoir reçu le PDF (code $($first.ExitCode))." }

# 3. Fermeture normale (enregistrement de l'état), puis lecture de l'historique.
$null = $first.CloseMainWindow()
if (-not $first.WaitForExit(20000)) {
  Write-Output '::warning title=Lancement réel (Windows)::OMNIA ne s''est pas fermé en 20 s ; arrêt forcé.'
  Stop-Process -Id $first.Id -Force
  # L'arrêt est asynchrone : tant que le processus existe, il garde le
  # fichier de l'historique ouvert en écriture.
  $null = $first.WaitForExit(15000)
}

# Dossier de données : %APPDATA%\<société>\<produit>\data (Runner.rc). On le
# cherche d'abord là, puis dans tout %APPDATA% si les ressources ont changé.
$history = Get-ChildItem -Path (Join-Path $env:APPDATA 'OMNIA') -Recurse -Filter 'history.hive' -ErrorAction SilentlyContinue |
  Select-Object -First 1
if (-not $history) {
  $history = Get-ChildItem -Path $env:APPDATA -Recurse -Filter 'history.hive' -ErrorAction SilentlyContinue |
    Select-Object -First 1
}
if (-not $history) { Fail "Aucun historique trouvé sous $env:APPDATA : le stockage local n'a pas été créé." }
Write-Output "Historique : $($history.FullName)"
# Lecture qui tolère un autre processus en écriture.
$stream = [System.IO.File]::Open($history.FullName, 'Open', 'Read', 'ReadWrite')
$buffer = New-Object System.IO.MemoryStream
$stream.CopyTo($buffer)
$stream.Dispose()
$content = [System.Text.Encoding]::UTF8.GetString($buffer.ToArray())

# Chaque écriture de l'historique ajoute une trame qui contient deux fois le
# chemin (clé et valeur). L'ouverture en écrit une première, avant même que le
# fichier soit lu : elle ne prouve que la réception de la commande. Une
# seconde trame n'arrive qu'après une lecture réussie :
# - PDF : pdfium a ouvert le document et publié sa page, OMNIA mémorise la page ;
# - son : libmpv a ouvert le fichier et publié sa durée (position mémorisée en
#   changeant de fichier), ou atteint sa fin (fichier marqué terminé). Les
#   machines de la CI n'ont pas de sortie audio : c'est l'ouverture et le
#   décodage qui sont prouvés, pas l'écoute.
foreach ($name in @('essai.wav', 'essai.pdf')) {
  $count = ([regex]::Matches($content, [regex]::Escape($name))).Count
  if ($count -eq 0) { Fail "$name est absent de l'historique : la commande d'ouverture n'est pas arrivée." }
  if ($count -lt 4) { Fail "$name a été reçu mais pas lu : libmpv ou pdfium n'ont pas pu l'ouvrir." }
}

Write-Output 'Lancement réel réussi : démarrage, son ouvert par libmpv, PDF confié par une seconde instance et ouvert par pdfium.'
