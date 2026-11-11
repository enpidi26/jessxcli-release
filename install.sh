#!/bin/sh
# Install jessx from the latest GitHub release (macOS and Linux).
#   curl -fsSL https://jessx.byenpidi.my.id/install.sh | sh
# JESSX_VERSION=v0.2.2 picks a release; JESSX_INSTALL_DIR sets where jessx goes
# (default ~/.local/bin), and it is added to PATH in your shell's rc file
# unless JESSX_NO_MODIFY_PATH=1. The command answers to two names, `jessx`
# and `jsx`; `jsx` is a link to `jessx`, and an older `jsx` found on the PATH
# is pointed at the new one. JESSX_UNINSTALL=1 removes both names; your
# settings and sessions in ~/.jsx are never touched.
set -eu

repo="enpidi26/jessxcli-release"
dir="${JESSX_INSTALL_DIR:-${JSX_INSTALL_DIR:-$HOME/.local/bin}}"

# Whether $1 is jessx (any version, under either name), going by what it
# says it is. Nothing else named jessx is ever touched.
is_jessx() {
  case "$("$1" --version 2>/dev/null | head -n 1)" in
    "jessx "* | "jsx "*) return 0 ;;
    *) return 1 ;;
  esac
}

if [ -n "${JESSX_UNINSTALL:-}" ]; then
  for name in jessx jsx; do
    if [ -e "$dir/$name" ] || [ -L "$dir/$name" ]; then
      rm -f "$dir/$name"
      echo "Removed $dir/$name"
    fi
  done
  # Links an install left elsewhere on the PATH, pointing here.
  old_ifs="$IFS"
  IFS=:
  for folder in $PATH; do
    for name in jsx jessx; do
      found="$folder/$name"
      if [ -L "$found" ] && [ "$(readlink "$found")" = "$dir/jessx" ]; then
        rm -f "$found"
        echo "Removed $found"
      fi
    done
  done
  IFS="$old_ifs"
  echo "Your settings and sessions in ~/.jsx are kept; delete that folder yourself if you want them gone."
  exit 0
fi

case "$(uname -s)" in
  Darwin) os=apple-darwin ;;
  Linux) os=unknown-linux-musl ;;
  *) echo "jessx: unsupported system $(uname -s); on Windows use install.ps1" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=x86_64 ;;
  arm64 | aarch64) arch=aarch64 ;;
  *) echo "jessx: unsupported processor $(uname -m)" >&2; exit 1 ;;
esac
target="$arch-$os"

ver="${JESSX_VERSION:-${JSX_VERSION:-}}"
if [ -n "$ver" ]; then
  url="https://github.com/$repo/releases/download/$ver/jessx-$target.tar.gz"
else
  url="https://github.com/$repo/releases/latest/download/jessx-$target.tar.gz"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "Downloading jessx for $target"
curl -fsSL "$url" -o "$tmp/jessx.tar.gz"
curl -fsSL "$url.sha256" -o "$tmp/jessx.tar.gz.sha256"
expected="$(cut -d' ' -f1 "$tmp/jessx.tar.gz.sha256")"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$tmp/jessx.tar.gz" | cut -d' ' -f1)"
else
  actual="$(shasum -a 256 "$tmp/jessx.tar.gz" | cut -d' ' -f1)"
fi
[ "$expected" = "$actual" ] || { echo "jessx: checksum mismatch, not installing" >&2; exit 1; }

tar xzf "$tmp/jessx.tar.gz" -C "$tmp"
mkdir -p "$dir"
mv "$tmp/jessx-$target/jessx" "$dir/jessx"
chmod +x "$dir/jessx"
# The release binary is unsigned; an ad-hoc signature lets macOS run it.
if [ "$os" = apple-darwin ]; then
  xattr -d com.apple.quarantine "$dir/jessx" 2>/dev/null || true
  codesign -f -s - "$dir/jessx" 2>/dev/null || true
fi

# `jsx`, the command's earlier name, runs the same binary.
ln -sf jessx "$dir/jsx"

version="$("$dir/jessx" --version | awk '{print $2}')"
echo "Installed jessx $version to $dir/jessx (also runs as jsx)"

# An older jessx installed somewhere else on the PATH (as `jessx` or `jessx`,
# for example by cargo) would still win in shells that search there first.
# Point each at this one, so no old version is left to run.
old_ifs="$IFS"
IFS=:
for folder in $PATH; do
  [ -n "$folder" ] && [ "$folder" != "$dir" ] || continue
  for name in jsx jessx; do
    found="$folder/$name"
    [ -f "$found" ] && [ -w "$folder" ] || continue
    [ "$(cd "$folder" && pwd -P)/$name" != "$(cd "$dir" && pwd -P)/jessx" ] || continue
    if [ -L "$found" ] && [ "$(readlink "$found")" = "$dir/jessx" ]; then continue; fi
    if is_jessx "$found"; then
      ln -sf "$dir/jessx" "$found"
      echo "Pointed the older $found at $dir/jessx"
    fi
  done
done
IFS="$old_ifs"

# Put $dir on PATH for new shells, once, in the rc file of the user's shell.
# JESSX_NO_MODIFY_PATH=1 leaves the shell config alone.
case ":$PATH:" in
  *":$dir:"*) exit 0 ;;
esac
if [ -n "${JESSX_NO_MODIFY_PATH:-${JSX_NO_MODIFY_PATH:-}}" ]; then
  echo "Add $dir to your PATH to run jessx."
  exit 0
fi
case "$(basename "${SHELL:-sh}")" in
  zsh) rc="${ZDOTDIR:-$HOME}/.zshrc"; line="export PATH=\"$dir:\$PATH\"" ;;
  bash)
    if [ "$os" = apple-darwin ]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi
    line="export PATH=\"$dir:\$PATH\""
    ;;
  fish) rc="$HOME/.config/fish/config.fish"; line="fish_add_path \"$dir\"" ;;
  *) rc="$HOME/.profile"; line="export PATH=\"$dir:\$PATH\"" ;;
esac
mkdir -p "$(dirname "$rc")"
if ! grep -qsF "$line" "$rc"; then
  printf '\n# jessx\n%s\n' "$line" >> "$rc"
fi
echo "Added $dir to PATH in $rc. Open a new terminal, or run: . \"$rc\""
