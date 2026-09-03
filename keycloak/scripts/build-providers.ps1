# build-providers.ps1 — Windows build of the Email Domain Guard provider JAR.
# Produces keycloak/providers/azul-domain-guard.jar with forward-slash entry
# names (Compress-Archive uses backslashes, which Java's JAR reader rejects).

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root 'providers-src'
$out  = Join-Path $root 'providers'
$jar  = Join-Path $out  'azul-domain-guard.jar'

New-Item -ItemType Directory -Force -Path $out | Out-Null
if (Test-Path $jar) { Remove-Item $jar }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$fs  = [System.IO.File]::Open($jar, [System.IO.FileMode]::Create)
$zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
function Add-Entry($archive, $file, $name) {
  $e  = $archive.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
  $es = $e.Open()
  $b  = [System.IO.File]::ReadAllBytes($file)
  $es.Write($b, 0, $b.Length); $es.Close()
}
Add-Entry $zip (Join-Path $src 'META-INF\keycloak-scripts.json') 'META-INF/keycloak-scripts.json'
Add-Entry $zip (Join-Path $src 'domain-check.js') 'domain-check.js'
$zip.Dispose(); $fs.Dispose()

Write-Host "Built $jar"
[System.IO.Compression.ZipFile]::OpenRead($jar).Entries | ForEach-Object { "  " + $_.FullName }
