#!/usr/bin/env bash
# bootstrap-dev-shell.sh
#
# Idempotent dev shell installer for Linux (Ubuntu 22.04+) and macOS.
# Installs: zsh, antidote, starship, fnm + Node LTS, uv, rustup + stable Rust,
# rtk, ccstatusline, caveman, bw (Bitwarden CLI), chezmoi, fzf, bat, eza,
# glow, zoxide, ripgrep, pip3, pulumi, tailscale.
#
# Safe to re-run: each step checks for prior install before acting.
# Does NOT chsh — run `chsh -s "$(command -v zsh)"` manually after verifying.
#
# Usage:
#   # pinned to a release tag (recommended — immutable):
#   curl -fsSL https://raw.githubusercontent.com/jjg-projects/dotfiles-bootstrap/v0.2.0/bootstrap-dev-shell.sh | bash
#
#   # or from a local clone:
#   ./bootstrap-dev-shell.sh
#
# Tags follow semver. Latest release:
#   https://github.com/jjg-projects/dotfiles-bootstrap/releases/latest

set -euo pipefail

# ---------- logging ----------

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$1" "$2"; }
ok()   { log "ok"    "$*"; }
skip() { log "skip"  "$*"; }
inst() { log "install" "$*"; }
warn() { log "warn"  "$*" >&2; }
die()  { log "fail"  "$*" >&2; exit 1; }

# ---------- environment detection ----------

OS="$(uname -s)"
case "$OS" in
  Linux)  PLATFORM="linux" ;;
  Darwin) PLATFORM="darwin" ;;
  *)      die "unsupported OS: $OS" ;;
esac

IS_WSL=0
if [[ "$PLATFORM" == "linux" ]] && grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
  IS_WSL=1
fi

SUDO=""
if [[ $EUID -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
fi

LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"
case ":$PATH:" in
  *":$LOCAL_BIN:"*) ;;
  *) export PATH="$LOCAL_BIN:$PATH" ;;
esac

log "env" "OS=$PLATFORM WSL=$IS_WSL user=$USER home=$HOME"

# ---------- helpers ----------

have() { command -v "$1" >/dev/null 2>&1; }

curl_to_bin() {
  local url="$1" name="$2" dest="$LOCAL_BIN/$name"
  curl --fail --location --silent --show-error -o "$dest" "$url"
  chmod +x "$dest"
}

# ---------- apt packages (linux only) ----------

install_apt_packages() {
  if [[ "$PLATFORM" != "linux" ]]; then
    skip "apt packages (not linux)"
    return
  fi

  local pkgs=(zsh fzf bat python3-pip unzip ca-certificates build-essential curl git)
  local missing=()
  for p in "${pkgs[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    skip "apt packages: all present"
    return
  fi

  inst "apt: ${missing[*]}"
  $SUDO apt-get update -qq
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"

  # Ubuntu installs bat as `batcat`; symlink to `bat` if needed.
  if have batcat && ! have bat; then
    ln -sf "$(command -v batcat)" "$LOCAL_BIN/bat"
    ok "bat symlinked from batcat"
  fi
}

# ---------- standalone binaries ----------

install_starship() {
  if have starship; then skip "starship"; return; fi
  inst "starship"
  curl --fail --location --silent --show-error https://starship.rs/install.sh \
    | sh -s -- --yes --bin-dir "$LOCAL_BIN" >/dev/null
}

install_fnm() {
  if have fnm; then skip "fnm"; return; fi
  inst "fnm"
  curl --fail --location --silent --show-error https://fnm.vercel.app/install \
    | bash -s -- --install-dir "$HOME/.local/share/fnm" --skip-shell >/dev/null
  ln -sf "$HOME/.local/share/fnm/fnm" "$LOCAL_BIN/fnm"
}

install_node_lts() {
  if ! have fnm; then die "fnm missing — install_fnm must run first"; fi
  # fnm lives in $HOME/.local/share/fnm; export its env for this script run.
  export FNM_DIR="$HOME/.local/share/fnm"
  export PATH="$FNM_DIR:$PATH"
  eval "$(fnm env --shell bash)"

  if fnm list 2>/dev/null | grep -q "lts-latest\|lts/"; then
    skip "Node LTS (fnm reports installed)"
  else
    inst "Node LTS via fnm"
    fnm install --lts
    fnm default lts-latest 2>/dev/null || fnm default "$(fnm list | grep -oE 'v[0-9.]+' | tail -1)"
  fi

  # Expose stable node/npm/npx in ~/.local/bin so tools that ship with a
  # `#!/usr/bin/env node` shebang (e.g. ccstatusline) resolve in any shell —
  # including non-interactive ones that don't eval `fnm env`. The fnm
  # `default` alias is a stable symlink so this never goes stale.
  local fnm_default_bin="$HOME/.local/share/fnm/aliases/default/bin"
  if [[ -d "$fnm_default_bin" ]]; then
    for b in node npm npx; do
      [[ -x "$fnm_default_bin/$b" ]] && ln -sf "$fnm_default_bin/$b" "$LOCAL_BIN/$b"
    done
  fi
}

install_eza() {
  if have eza; then skip "eza"; return; fi
  inst "eza"
  if [[ "$PLATFORM" == "darwin" ]]; then
    have brew && brew install eza && return
  fi
  # Linux: prefer apt if available (Ubuntu 24.04 has it), else GitHub release.
  if [[ "$PLATFORM" == "linux" ]] && apt-cache show eza >/dev/null 2>&1; then
    $SUDO apt-get install -y eza
  else
    local arch="x86_64" url
    [[ "$(uname -m)" == "aarch64" || "$(uname -m)" == "arm64" ]] && arch="aarch64"
    url="https://github.com/eza-community/eza/releases/latest/download/eza_${arch}-unknown-linux-gnu.tar.gz"
    local tmp
    tmp="$(mktemp -d)"
    curl --fail --location --silent --show-error -o "$tmp/eza.tgz" "$url"
    tar -xzf "$tmp/eza.tgz" -C "$tmp"
    mv "$tmp/eza" "$LOCAL_BIN/eza"
    chmod +x "$LOCAL_BIN/eza"
    rm -rf "$tmp"
  fi
}

install_glow() {
  # Charm's terminal markdown renderer. Useful for reading README files inline
  # and previewing markdown in pipelines (e.g. `glow README.md`, `cat foo.md | glow -`).
  if have glow; then skip "glow"; return; fi
  inst "glow (terminal markdown renderer)"
  if [[ "$PLATFORM" == "darwin" ]] && have brew; then
    brew install glow && return
  fi
  # Linux: download the release tarball from GitHub. Charm does publish an
  # apt repo, but it requires sudo + keyring setup; a static binary in
  # ~/.local/bin keeps the install side-effect-free.
  local arch tmp url ver bin
  case "$(uname -m)" in
    x86_64)        arch="x86_64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "unsupported glow arch: $(uname -m)" ;;
  esac
  # Resolve latest version from the GitHub API. Falls back to a known-good
  # pin if the API is rate-limited or unreachable.
  ver="$(curl --fail --silent --show-error \
    https://api.github.com/repos/charmbracelet/glow/releases/latest 2>/dev/null \
    | sed -nE 's/.*"tag_name":[[:space:]]*"v([^"]+)".*/\1/p' | head -1)"
  if [[ -z "$ver" ]]; then
    warn "glow: GitHub API lookup failed, falling back to pinned v2.1.1"
    ver="2.1.1"
  fi
  tmp="$(mktemp -d)"
  url="https://github.com/charmbracelet/glow/releases/download/v${ver}/glow_${ver}_Linux_${arch}.tar.gz"
  curl --fail --location --silent --show-error -o "$tmp/glow.tgz" "$url"
  tar -xzf "$tmp/glow.tgz" -C "$tmp"
  # Tarball layout has shifted across releases (sometimes flat, sometimes a
  # versioned subdir); locate the binary instead of hardcoding the path.
  bin="$(find "$tmp" -maxdepth 3 -name glow -type f -perm -u+x | head -1)"
  [[ -z "$bin" ]] && die "glow: binary not found in extracted tarball"
  mv "$bin" "$LOCAL_BIN/glow"
  chmod +x "$LOCAL_BIN/glow"
  rm -rf "$tmp"
}

install_zoxide() {
  if have zoxide; then skip "zoxide"; return; fi
  inst "zoxide"
  curl --fail --location --silent --show-error \
    https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh \
    | bash -s -- --bin-dir "$LOCAL_BIN" >/dev/null
}

install_chezmoi() {
  if have chezmoi; then skip "chezmoi"; return; fi
  inst "chezmoi"
  curl --fail --location --silent --show-error get.chezmoi.io \
    | sh -s -- -b "$LOCAL_BIN" >/dev/null
}

install_rtk() {
  if have rtk; then skip "rtk"; return; fi
  inst "rtk"
  curl --fail --location --silent --show-error \
    https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh \
    | sh >/dev/null
  # rtk installer drops binary somewhere on PATH; verify.
  have rtk || warn "rtk installer ran but binary not on PATH — check installer output"
}

# Separate from install_rtk so it runs on machines where the binary already
# exists but Claude Code hasn't been configured to route Bash through rtk.
# Detection grep matches rtk's own --show output for the unconfigured state.
configure_rtk_hook() {
  if ! have rtk; then return; fi
  if ! rtk init -g --show 2>/dev/null \
      | grep -qE "Hook: not found|RTK hook not configured"; then
    skip "rtk hook"
    return
  fi
  inst "rtk hook (claude code)"
  rtk init -g --auto-patch >/dev/null 2>&1 \
    || warn "rtk init -g failed — run 'rtk init -g --auto-patch' manually"
}

install_bw() {
  if have bw; then skip "bw"; return; fi
  inst "bw (Bitwarden CLI)"
  if [[ "$PLATFORM" == "darwin" ]] && have brew; then
    brew install bitwarden-cli && return
  fi
  # Linux: download zip from official Bitwarden release.
  local tmp
  tmp="$(mktemp -d)"
  curl --fail --location --silent --show-error \
    -o "$tmp/bw.zip" \
    "https://vault.bitwarden.com/download/?app=cli&platform=linux"
  unzip -q "$tmp/bw.zip" -d "$tmp"
  mv "$tmp/bw" "$LOCAL_BIN/bw"
  chmod +x "$LOCAL_BIN/bw"
  rm -rf "$tmp"
}

install_bun() {
  # Check both PATH and the canonical install location, since this script may
  # run with a fresh PATH that doesn't yet include ~/.bun/bin.
  if have bun || [[ -x "$HOME/.bun/bin/bun" ]]; then
    [[ -d "$HOME/.bun/bin" ]] && export PATH="$HOME/.bun/bin:$PATH"
    skip "bun"
    return
  fi
  inst "bun"
  curl --fail --location --silent --show-error https://bun.sh/install \
    | bash >/dev/null
  [[ -d "$HOME/.bun/bin" ]] && export PATH="$HOME/.bun/bin:$PATH"
}

install_ccstatusline() {
  if have ccstatusline; then skip "ccstatusline"; return; fi
  if ! have bun; then die "bun missing — install_bun must run first"; fi
  inst "ccstatusline (bun global)"
  bun install -g ccstatusline >/dev/null
  # bun's global bin is ~/.bun/bin; verify ccstatusline ended up there.
  [[ -d "$HOME/.bun/bin" ]] && export PATH="$HOME/.bun/bin:$PATH"
}

install_antidote() {
  if [[ -d "$HOME/.antidote" ]]; then skip "antidote"; return; fi
  inst "antidote"
  git clone --quiet --depth=1 https://github.com/mattmc3/antidote.git "$HOME/.antidote"
}

install_uv() {
  if have uv; then skip "uv"; return; fi
  inst "uv (Python package + version manager)"
  # UV_NO_MODIFY_PATH=1: our zshrc template already prepends ~/.local/bin,
  # so we don't want uv's installer rewriting shell rc files on top of it.
  curl --fail --location --silent --show-error https://astral.sh/uv/install.sh \
    | env UV_NO_MODIFY_PATH=1 sh >/dev/null
}

install_rust() {
  # rustup installs into ~/.cargo + ~/.rustup. cargo binary is the canonical
  # PATH probe; zshrc adds ~/.cargo/bin so subsequent shells see it.
  if have cargo || [[ -x "$HOME/.cargo/bin/cargo" ]]; then
    [[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"
    skip "rust (rustup)"
    return
  fi
  inst "rust (rustup, stable toolchain)"
  # --no-modify-path: zshrc owns PATH (mirrors install_uv).
  # default profile: rustc, cargo, rust-std, rust-docs, rustfmt, clippy.
  curl --fail --proto '=https' --tlsv1.2 --location --silent --show-error \
    https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --default-toolchain stable --profile default >/dev/null
  [[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"
}

install_caveman() {
  # Caveman is a Claude Code plugin and also installs into codex/gemini/etc.
  # when their CLIs are on PATH at install time. No CLI lands on PATH, so
  # probe each target's registry/extension dir. To force a reinstall:
  #   rm -rf ~/.gemini/extensions/caveman ~/.codex/extensions/caveman
  #   # and remove the "caveman@caveman" entry from
  #   # ~/.claude/plugins/installed_plugins.json
  local plugins_json="$HOME/.claude/plugins/installed_plugins.json"
  # Claude plugin registry stores keys as "<name>@<source>", e.g. "caveman@caveman".
  if [[ -f "$plugins_json" ]] && grep -q '"caveman@' "$plugins_json" 2>/dev/null; then
    skip "caveman (claude)"
    return
  fi
  # Even when not in the Claude registry, the npx installer refuses to proceed
  # if the gemini/codex extension dir already exists. Treat either as installed.
  if [[ -d "$HOME/.gemini/extensions/caveman" ]] || [[ -d "$HOME/.codex/extensions/caveman" ]]; then
    skip "caveman (gemini/codex)"
    return
  fi
  if ! have npx; then die "npx missing — install_node_lts must run first"; fi
  inst "caveman (token-compression skill)"
  npx -y "github:JuliusBrussee/caveman" --non-interactive >/dev/null
}

install_pulumi() {
  # Pulumi installs to ~/.pulumi/bin/pulumi; chezmoi-managed zshrc adds it to PATH.
  if have pulumi || [[ -x "$HOME/.pulumi/bin/pulumi" ]]; then
    [[ -d "$HOME/.pulumi/bin" ]] && export PATH="$HOME/.pulumi/bin:$PATH"
    skip "pulumi"
    return
  fi
  inst "pulumi"
  curl --fail --location --silent --show-error https://get.pulumi.com \
    | sh >/dev/null
  [[ -d "$HOME/.pulumi/bin" ]] && export PATH="$HOME/.pulumi/bin:$PATH"
}

install_tailscale() {
  # Official installer auto-detects apt/dnf/brew and registers the daemon.
  # Does not run `tailscale up` — that requires interactive browser auth and
  # should be done once per host by the operator.
  if have tailscale; then skip "tailscale"; return; fi
  inst "tailscale"
  curl --fail --location --silent --show-error https://tailscale.com/install.sh \
    | sh >/dev/null
}

# ---------- main ----------

main() {
  install_apt_packages
  install_starship
  install_fnm
  install_node_lts
  install_uv
  install_rust
  install_eza
  install_glow
  install_zoxide
  install_chezmoi
  install_rtk
  configure_rtk_hook
  install_bw
  install_bun
  install_ccstatusline
  install_caveman
  install_antidote
  install_pulumi
  install_tailscale

  echo
  ok "bootstrap complete"
  echo
  log "next" "1. Review tools: starship --version, fnm --version, cargo --version, rtk --version, bw --version, chezmoi --version"
  log "next" "2. (optional) Make zsh your default shell:  chsh -s \"\$(command -v zsh)\""
  log "next" "3. Apply dotfiles:  chezmoi init <repo-url>  &&  chezmoi apply"
  log "next" "4. Bitwarden login:  bw login   (interactive, one-time)"
  log "next" "5. Tailscale up:      sudo tailscale up   (interactive browser auth, per-host)"
}

main "$@"
