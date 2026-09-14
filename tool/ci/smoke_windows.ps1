# Lancement réel d'OMNIA sur la machine Windows de la CI.
#
# 1. OMNIA démarre avec un son en argument, comme par « Ouvrir avec », et doit
#    rester ouvert : libmpv, la fenêtre et le stockage local se sont initialisés.
# 2. Une seconde instance reçoit un PDF, comme un fichier déposé sur l'icône :
#    elle doit le confier à la première fenêtre et se terminer aussitôt.
# 3. Après fermeture, l'historique doit contenir les deux fichiers : les deux
#    ouvertures ont réellement eu lieu.
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

# Fin d'un journal, encodée pour tenir dans une annotation.
function Get-LogTail([string] $path) {
  if (-not (Test-Path $path)) { return '' }
  $lines = Get-Content -Path $path -Tail 30 -ErrorAction SilentlyContinue
  return (($lines -join "`n") -replace '%', '%25' -replace "`r", '' -replace "`n", '%0A')
}

function Fail([string] $message) {
  $tail = Get-LogTail (Join-Path $OutDir 'omnia-stderr.txt')
  if ($tail) { $message = "$message%0A%0ASortie d'erreur d'OMNIA :%0A$tail" }
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

# 1. Première instance, avec le son.
$first = Start-Omnia $wav 'omnia'
Start-Sleep -Seconds 20
Save-Screen '1-lecture-audio.png'
if ($first.HasExited) { Fail "OMNIA s'est arrêté au démarrage (code $($first.ExitCode))." }

# 2. Seconde instance, avec le PDF : elle doit déléguer et se retirer.
$second = Start-Omnia $pdf 'seconde-instance'
if (-not $second.WaitForExit(30000)) {
  Save-Screen '2-seconde-instance.png'
  Fail 'La seconde instance est restée ouverte : le PDF n''a pas été confié à la première fenêtre.'
}
if ($second.ExitCode -ne 0) { Fail "La seconde instance s'est terminée en erreur (code $($second.ExitCode))." }
Start-Sleep -Seconds 10
Save-Screen '2-document-pdf.png'
if ($first.HasExited) { Fail "OMNIA s'est arrêté après avoir reçu le PDF (code $($first.ExitCode))." }

# 3. Fermeture normale (enregistrement de l'état), puis lecture de l'historique.
$null = $first.CloseMainWindow()
if (-not $first.WaitForExit(20000)) {
  Write-Output '::warning title=Lancement réel (Windows)::OMNIA ne s''est pas fermé en 20 s ; arrêt forcé.'
  Stop-Process -Id $first.Id -Force
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
$content = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($history.FullName))
foreach ($name in @('essai.wav', 'essai.pdf')) {
  if (-not $content.Contains($name)) { Fail "$name est absent de l'historique : son ouverture n'a pas eu lieu." }
}

Write-Output 'Lancement réel réussi : démarrage, ouverture du son, PDF confié par une seconde instance.'
