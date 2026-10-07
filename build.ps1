$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$profileDirectory = Join-Path $PSScriptRoot 'Librarian-Win64-Shipping'
$outputDirectory = Join-Path $PSScriptRoot 'dist'
$archivePath = Join-Path $outputDirectory 'Librarian-Win64-Shipping.zip'
$includedFiles = @(
    'config.txt'
    'scripts/librarian_pointer.lua'
    'scripts/librarian_vr_comfort.lua'
    'data/librarian-pointer-module.lua'
    'data/librarian-pointer-settings.json'
)
foreach ($relativePath in $includedFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $profileDirectory $relativePath) -PathType Leaf)) {
        throw "Missing profile file: $relativePath"
    }
}
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath }
$archive = [System.IO.Compression.ZipFile]::Open($archivePath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($relativePath in $includedFiles) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive,
            (Join-Path $profileDirectory $relativePath),
            $relativePath,
            [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
} finally { $archive.Dispose() }
Get-Item -LiteralPath $archivePath | Select-Object FullName, Length
