# Install jessx from the latest GitHub release (Windows).
#   irm https://jessx.byenpidi.my.id/install.ps1 | iex
# $env:JESSX_VERSION = "v0.2.2" picks a release; $env:JESSX_INSTALL_DIR sets where
# jessx goes (default %LOCALAPPDATA%\Programs\jessx). The command answers to two
# names, jessx and jsx (jsx.exe is a copy of jessx.exe), and an older jsx.exe or
# jessx.exe found on the PATH is replaced with this one. $env:JESSX_UNINSTALL = 1
# removes both; your settings and sessions in ~\.jsx are never touched.
$ErrorActionPreference = "Stop"

$repo = "enpidi26/jessxcli-release"
$dir = if ($env:JESSX_INSTALL_DIR) { $env:JESSX_INSTALL_DIR } elseif ($env:JSX_INSTALL_DIR) { $env:JSX_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "Programs\jessx" }

# Whether a program is jessx (any version, under either name), going by what
# it says it is. Nothing else named enx is ever touched.
function Test-Jessx($path) {
  try {
    $line = (& $path --version 2>$null | Select-Object -First 1)
    return ($line -like "jessx *") -or ($line -like "jsx *")
  } catch { return $false }
}

if ($env:JESSX_UNINSTALL) {
  foreach ($name in @("jessx.exe", "jsx.exe")) {
    $path = Join-Path $dir $name
    if (Test-Path $path) { Remove-Item -Force $path; Write-Host "Removed $path" }
  }
  Write-Host "Your settings and sessions in ~\.jsx are kept; delete that folder yourself if you want them gone."
  return
}
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x86_64" }
$target = "$arch-pc-windows-msvc"
$ver = if ($env:JESSX_VERSION) { $env:JESSX_VERSION } elseif ($env:JSX_VERSION) { $env:JSX_VERSION } else { "" }
$url = if ($ver) {
  "https://github.com/$repo/releases/download/$ver/jessx-$target.zip"
} else {
  "https://github.com/$repo/releases/latest/download/jessx-$target.zip"
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
try {
  Write-Host "Downloading jessx for $target"
  $zip = Join-Path $tmp "jessx.zip"
  Invoke-WebRequest $url -OutFile $zip -UseBasicParsing
  Invoke-WebRequest "$url.sha256" -OutFile "$zip.sha256" -UseBasicParsing
  $expected = (Get-Content "$zip.sha256").Split(" ")[0].Trim()
  $actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
  if ($expected -ne $actual) { throw "checksum mismatch, not installing" }

  Expand-Archive $zip -DestinationPath $tmp
  New-Item -ItemType Directory -Force $dir | Out-Null
  $fresh = Join-Path $tmp "jessx-$target\jessx.exe"
  # A running .exe cannot be overwritten, but can be moved aside.
  foreach ($name in @("jessx", "jsx")) {
    $path = Join-Path $dir "$name.exe"
    if (Test-Path $path) {
      $old = Join-Path $dir "$name.old.exe"
      Remove-Item -Force $old -ErrorAction SilentlyContinue
      Move-Item -Force $path $old
    }
    Copy-Item $fresh $path -Force
  }
} finally {
  Remove-Item -Recurse -Force $tmp
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (($userPath -split ";") -notcontains $dir) {
  [Environment]::SetEnvironmentVariable("Path", "$userPath;$dir", "User")
  Write-Host "Added $dir to your PATH; open a new terminal to use jessx."
}
$version = ((& (Join-Path $dir "jessx.exe") --version) -split " ")[1]
Write-Host "Installed jessx $version to $dir\jessx.exe (also runs as jsx)"

# An older jessx elsewhere on the PATH (as jsx.exe or jessx.exe) would still
# run in a shell that finds it first: replace it with this one.
$here = (Resolve-Path $dir).Path.TrimEnd("\")
foreach ($name in @("jsx", "jessx")) {
  foreach ($found in @(Get-Command "$name.exe" -All -CommandType Application -ErrorAction SilentlyContinue)) {
    $path = $found.Source
    if ((Split-Path $path -Parent).TrimEnd("\") -eq $here) { continue }
    if (-not (Test-Jessx $path)) { continue }
    try {
      $old = [IO.Path]::ChangeExtension($path, "old.exe")
      Remove-Item -Force $old -ErrorAction SilentlyContinue
      Move-Item -Force $path $old
      Copy-Item (Join-Path $dir "jessx.exe") $path -Force
      Write-Host "Replaced the older $path with this jessx"
    } catch {
      Write-Host "Could not replace the older $path ($($_.Exception.Message)); remove it, or put $dir first on your PATH."
    }
  }
}

