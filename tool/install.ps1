# Installs the command line interface of Laska on Windows.
#
#   irm https://raw.githubusercontent.com/tenderowl/laska/main/tool/install.ps1 | iex
#
# The options:
#   -Version <version>  The version to install. Defaults to the latest one.
#   -Home <directory>   Where the command is installed. Defaults to
#                       %LOCALAPPDATA%\laska.
#
# The script checks the checksum of the bundle it downloads before it unpacks
# it.
[CmdletBinding()]
param(
  [string]$Version = '',
  [string]$Home = ''
)

$ErrorActionPreference = 'Stop'

$Repository = 'tenderowl/laska'

if ([string]::IsNullOrEmpty($Home)) {
  $Home = Join-Path $env:LOCALAPPDATA 'laska'
}

switch ($env:PROCESSOR_ARCHITECTURE) {
  'AMD64' { $Architecture = 'x64' }
  'ARM64' { $Architecture = 'arm64' }
  default {
    Write-Error "Laska is not built for this architecture: $env:PROCESSOR_ARCHITECTURE."
    exit 1
  }
}

if ([string]::IsNullOrEmpty($Version)) {
  Write-Host 'Looking for the latest version...'
  $Release = Invoke-RestMethod "https://api.github.com/repos/$Repository/releases/latest"
  $Version = $Release.tag_name.TrimStart('v')
}

if ([string]::IsNullOrEmpty($Version)) {
  Write-Error 'The latest version could not be found.'
  exit 1
}

$Asset = "laska-windows-$Architecture.zip"
$Base = "https://github.com/$Repository/releases/download/v$Version"

$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("laska_install_" + [System.Guid]::NewGuid())
New-Item -ItemType Directory -Path $Work -Force | Out-Null

try {
  Write-Host "Downloading Laska $Version for windows-$Architecture..."
  $Archive = Join-Path $Work $Asset
  Invoke-WebRequest -Uri "$Base/$Asset" -OutFile $Archive
  Invoke-WebRequest -Uri "$Base/$Asset.sha256" -OutFile "$Archive.sha256"

  # The checksum of the bundle is checked before it is unpacked: the command
  # that runs on the machine of the user is the one that was built by the
  # project.
  $Expected = ((Get-Content "$Archive.sha256") -split '\s+')[0].ToLower()
  $Actual = (Get-FileHash -Path $Archive -Algorithm SHA256).Hash.ToLower()

  if ($Expected -ne $Actual) {
    Write-Error 'The checksum of the bundle does not match: the download was changed on the way.'
    exit 1
  }

  New-Item -ItemType Directory -Path $Home -Force | Out-Null
  Expand-Archive -Path $Archive -DestinationPath $Home -Force

  Write-Host ''
  Write-Host "Laska $Version is installed in $Home."
  Write-Host ''
  Write-Host 'Add it to the PATH for the current session:'
  Write-Host "  `$env:PATH = `"$Home\bin;`$env:PATH`""
  Write-Host ''
  Write-Host 'Then run:'
  Write-Host '  laska new shop'
}
finally {
  Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}
