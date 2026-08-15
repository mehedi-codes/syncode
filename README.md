# VS Code Config

Personal Visual Studio Code configuration — live sync, merged history, and documentation.

## Current setup

| Area | Setting |
|---|---|
| **Theme** | `Vercel Dark` |
| **Icons** | `charmed-icons` (files) · `fluent-icons` (product) |
| **Font** | `DankMono Nerd Font` — 16px, ligatures on |
| **Layout** | Zen/minimal: activity bar hidden, status bar hidden, breadcrumbs off, single tabs, command center off, no minimap, hidden scrollbars |
| **Formatting** | `biomejs.biome` default formatter; format on save/type/paste; 2-space tabs, ruler @140, wrap @140 |
| **Terminal** | Git Bash (Windows default), DankMono font, line cursor |
| **Git** | Smart commit, autofetch, no sync confirm, auto-update imports on file move |
| **Privacy** | Telemetry off, trusted JSON-schema domains whitelist |
| **Editor niceties** | Expand cursor blink, smooth scrolling, bracket colorization, italic comments, hover after 1.5s |
| **Files** | Auto-save after delay, trim trailing whitespace + final newline, `css→tailwindcss` / `cshtml→html` / `appsettings*.json→jsonc` associations |

> Full per-setting explanations and alternative values: [`settings.md`](./settings.md). Annotated history: [`settings.jsonc`](./settings.jsonc).

## Files

| File | Purpose |
|---|---|
| `settings.json` | **Live config** — symlink to `%APPDATA%\Code\User\settings.json`. Edit here → VS Code updates instantly (and vice versa). Not tracked in git (see `.gitignore`). |
| `settings.jsonc` | **Merged reference** — every setting across all config eras (2023 → current), annotated with era tags and `was:` history. VS Code won't load this; it's the archive + source of truth. |
| `settings.md` | Explanations — what each setting does and every value it accepts. |
| `extensions.jsonc` | Merged extension list across eras (current / 2025-10 / 2025-04). |
| `extensions.md` | Clickable extension links — **Ctrl+click** opens the extension page inside VS Code (not the browser). |
| `AGENTS.md` | VS Code documentation index (llms.txt format) — a docs map for AI agents. |
| `vscodium.md` | The original VSCodium setup guide (archived). |

## How the sync works

- `settings.json` is a **symbolic link** to `%APPDATA%\Code\User\settings.json` (Windows, cross-volume OK — symlink, not hard link).
- Requires Windows **Developer Mode** (or one-time admin) to create.
- Git ignores it (`core.symlinks` issue — the link would be committed as path text otherwise). It lives in the repo only as a live-editing convenience.
- To re-create the link: `New-Item -ItemType SymbolicLink -Path settings.json -Target "$env:APPDATA\Code\User\settings.json"`

## Updating configs

1. Edit `settings.jsonc` (the annotated reference) for history-tracking.
2. Apply live changes in `settings.json` (via the symlink) or copy values over.
3. Keep `settings.md` explanations in sync for anything new.

## Compatibility

Settings format is shared across VS Code forks (VSCodium, Cursor, Windsurf, Positron) — the user/workspace/profile hierarchy and these files carry over; only config *paths* and marketplaces differ.