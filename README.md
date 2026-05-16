# dotfiles-bootstrap

Idempotent dev shell installer for Linux (Ubuntu 22.04+) and macOS. Sets up a productive zsh + modern CLI environment on a fresh machine with one command.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/jjg-projects/dotfiles-bootstrap/main/bootstrap-dev-shell.sh | bash
```

Safe to re-run. Each step checks for prior install before acting.

## What it installs

| Category | Tool | Purpose |
|----------|------|---------|
| Shell | `zsh`, `antidote` | Shell + plugin manager |
| Prompt | `starship` | Cross-platform prompt |
| Node | `fnm` + Node LTS, `bun` | Version manager, runtime, JS package manager |
| Python | `uv` | Package + version manager |
| Rust | `rustup` + stable toolchain | `rustc`, `cargo`, `rustfmt`, `clippy` |
| Claude Code | `caveman`, `rtk`, `ccstatusline` | Token-compression skill, CLI proxy, statusline formatter |
| Secrets | `bw` | Bitwarden CLI |
| Dotfiles | `chezmoi` | Cross-machine dotfiles manager |
| CLI QoL | `fzf`, `bat`, `eza`, `zoxide`, `ripgrep`, `pip3` | Standard set |
| IaC | `pulumi` | Infrastructure as Code |
| Networking | `tailscale` | Mesh VPN (no `tailscale up` — interactive) |

## After bootstrap

The script does **not** change your login shell. Make zsh default:

```bash
chsh -s "$(command -v zsh)"
```

This script installs *tools only*. Personal dotfiles (zshrc, starship.toml, plugin config) are managed separately via `chezmoi`. Point it at your own dotfiles repo:

```bash
chezmoi init <your-dotfiles-repo>
chezmoi apply
```

## Platforms

- Linux: Ubuntu 22.04+ (including WSL2)
- macOS: Apple Silicon and Intel (Homebrew required)

## License

[MIT](LICENSE)
