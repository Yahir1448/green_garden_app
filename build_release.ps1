<#
.SYNOPSIS
  Compila la app y guarda cada versión en releases\v<version>\.

.EXAMPLES
  .\build_release.ps1                  # compila APK + AAB con la versión actual de pubspec.yaml
  .\build_release.ps1 -SubirBuild      # primero suma 1 al número de build (1.0.0+1 -> 1.0.0+2)
  .\build_release.ps1 -Tipo apk        # solo APK (para instalar directo en un teléfono)
  .\build_release.ps1 -Notas "Agrega exportación de datos"

  Si PowerShell bloquea el script, ejecútalo una vez con:
  powershell -ExecutionPolicy Bypass -File .\build_release.ps1
#>
param(
  [ValidateSet('apk', 'appbundle', 'both')]
  [string]$Tipo = 'both',

  [switch]$SubirBuild,

  [string]$Notas = ''
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$utf8SinBom = New-Object System.Text.UTF8Encoding($false)
$pubspec = Join-Path $PSScriptRoot 'pubspec.yaml'

# --- 1) Subir el número de build si se pidió -------------------------------
if ($SubirBuild) {
  $contenido = [System.IO.File]::ReadAllText($pubspec, [System.Text.Encoding]::UTF8)
  $nuevo = [regex]::Replace(
    $contenido,
    '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)',
    { param($m) "version: $($m.Groups[1].Value)+$([int]$m.Groups[2].Value + 1)" }
  )
  if ($nuevo -eq $contenido) {
    throw "No pude subir el build: la línea 'version:' de pubspec.yaml debe verse como 1.0.0+1"
  }
  [System.IO.File]::WriteAllText($pubspec, $nuevo, $utf8SinBom)
}

# --- 2) Leer la versión ----------------------------------------------------
$texto = [System.IO.File]::ReadAllText($pubspec, [System.Text.Encoding]::UTF8)
$m = [regex]::Match($texto, '(?m)^version:\s*(\S+)')
if (-not $m.Success) { throw "No encontré la línea 'version:' en pubspec.yaml" }
$version = $m.Groups[1].Value   # ej. 1.0.0+1

$carpeta = Join-Path $PSScriptRoot "releases\v$version"
if (Test-Path $carpeta) {
  throw "Ya existe $carpeta. Sube la versión en pubspec.yaml (o usa -SubirBuild) para no sobrescribirla."
}

Write-Host "Compilando versión $version ..." -ForegroundColor Green

# --- 3) Compilar -----------------------------------------------------------
$apk = Join-Path $PSScriptRoot 'build\app\outputs\flutter-apk\app-release.apk'
$aab = Join-Path $PSScriptRoot 'build\app\outputs\bundle\release\app-release.aab'

# Borra restos de compilaciones anteriores para no archivar por error un
# archivo viejo con el número de versión nuevo.
Remove-Item $apk, $aab -ErrorAction SilentlyContinue

flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get falló' }

$fallos = @()
if ($Tipo -eq 'apk' -or $Tipo -eq 'both') {
  flutter build apk --release
  if ($LASTEXITCODE -ne 0) { $fallos += 'APK' }
}
if ($Tipo -eq 'appbundle' -or $Tipo -eq 'both') {
  flutter build appbundle --release
  if ($LASTEXITCODE -ne 0) { $fallos += 'AAB' }
}

if (-not ((Test-Path $apk) -or (Test-Path $aab))) {
  throw 'No se generó ningún archivo. Revisa los errores de arriba.'
}

# --- 4) Guardar en releases\v<version> -------------------------------------
New-Item -ItemType Directory -Path $carpeta | Out-Null

if (Test-Path $apk) { Copy-Item $apk (Join-Path $carpeta "green_garden-$version.apk") }
if (Test-Path $aab) { Copy-Item $aab (Join-Path $carpeta "green_garden-$version.aab") }

# --- 5) Ficha de la versión ------------------------------------------------
$commit = ''
$sucio = ''
if (Get-Command git -ErrorAction SilentlyContinue) {
  $commit = (git rev-parse --short HEAD 2>$null)
  if ((git status --porcelain 2>$null)) { $sucio = ' (con cambios sin guardar en git)' }
}

$ficha = @(
  "Versión:  $version",
  "Fecha:    $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
  "Commit:   $commit$sucio",
  "Notas:    $Notas"
)
if ($fallos.Count -gt 0) { $ficha += "Fallaron: $($fallos -join ', ')" }
[System.IO.File]::WriteAllText((Join-Path $carpeta 'NOTAS.txt'), ($ficha -join "`r`n"), $utf8SinBom)

Write-Host ''
Write-Host "Listo. Guardado en: $carpeta" -ForegroundColor Green
Get-ChildItem $carpeta | ForEach-Object { Write-Host "  - $($_.Name)" }
if ($fallos.Count -gt 0) {
  Write-Host ''
  Write-Host "ATENCION: falló la compilación de: $($fallos -join ', '). No está en la carpeta." -ForegroundColor Yellow
}