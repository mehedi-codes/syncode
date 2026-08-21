# Extensions

Curated, general-purpose, language-agnostic extensions installed by `syncode`.
Each editor has its own list: `code/extensions.json`, `codium/extensions.json`
(both Open VSX / Microsoft Marketplace IDs), and `zed/extensions.json` (Zed
registry IDs). Grouped by the same `//!` sections as the configs.

## Install

```bash
codium --install-extension <id>     # VSCodium / any fork with a CLI
code --install-extension <id>       # VS Code
```

Zed has no extension CLI — syncode writes its picks into
`auto_install_extensions` in Zed's `settings.json` and Zed downloads them on
next launch.

Versions below are the latest at time of writing — install by ID so updates
apply automatically.

---

## Visual / UI

### `littensy.charmed-icons` — Charmed Icons · 0.10.0

[Open VSX](https://open-vsx.org/extension/littensy/charmed-icons) · [GitHub](https://github.com/littensy/charmed-icons)

File icon theme. Ships four themes — **Charmed**, **Charmed Light**,
**Charmed Soft**, **Charmed Warm** — originally aimed at Roblox codebases but
works for any project.

**Usage:** activate via Command Palette → *Preferences: File Icon Theme* →
pick one of the Charmed variants.

**Settings** (`settings.json` already sets `workbench.iconTheme` and
`charmed-icons.hidesExplorerArrows`):

| Setting | Default | Description |
| --- | --- | --- |
| `charmed-icons.hidesExplorerArrows` | `false` | Hide arrows next to folders in the explorer |
| `charmed-icons.outlineFolders` | `"when-expanded"` | Folder outline style: `always`, `when-expanded`, `never` |
| `charmed-icons.associations.languages` | `{}` | Custom language-id → icon mappings |
| `charmed-icons.associations.extensions` | `{}` | Custom file-extension → icon mappings |
| `charmed-icons.associations.files` | `{}` | Custom file-name → icon mappings |
| `charmed-icons.associations.folders` | `{}` | Custom folder-name → icon mappings |

No commands or keybindings.

---

### `subframe7536.custom-ui-style` — Custom UI Style · 0.7.1

[Open VSX](https://open-vsx.org/extension/subframe7536/custom-ui-style) · [GitHub](https://github.com/subframe7536/vscode-custom-ui-style)

Injects custom CSS/JS into the editor UI and webviews by patching core files.
On first install (or after every VS Code-family update) it prompts to back up
the original files.

**Usage:**
- Add CSS via `custom-ui-style.stylesheet` (nested selectors supported)
- Apply/roll back: Command Palette → **Custom UI Style: Reload** /
  **Rollback** (restores patched originals)
- ⚠️ Modifies the editor's installation files; author notes it's untested on
  Linux and forks like Cursor

**Commands:** `custom-ui-style.reload`, `custom-ui-style.rollback`,
`custom-ui-style.cleanup`

**Settings** (`settings.json` already sets `custom-ui-style.stylesheet`;
the repo's CSS targets `.sidebar`, `.title-actions`, `.quick-input-widget`):

| Setting | Default | Description |
| --- | --- | --- |
| `custom-ui-style.stylesheet` | `{}` | Custom CSS for the editor; nested selectors |
| `custom-ui-style.background.url` | `""` | Full-screen background image URL (`https://`, `file://`, `data:`) — not synced |
| `custom-ui-style.background.syncURL` | `""` | Same, synced; supports `${userHome}` / `${env:VAR:fallback}` variables |
| `custom-ui-style.background.opacity` | `0.9` | Background image opacity (0–1) |
| `custom-ui-style.background.size` | `"cover"` | Background size (`cover`, `contain`, …) |
| `custom-ui-style.background.position` | `"center"` | Background position |
| `custom-ui-style.font.monospace` | `""` | Global monospace font family (editor + webviews) |
| `custom-ui-style.font.sansSerif` | `""` | Global sans-serif font family (editor + webviews) |
| `custom-ui-style.electron` | `{}` | Electron BrowserWindow options (e.g. frameless window) |
| `custom-ui-style.watch` | `true` | Auto-reload window on config changes (ignores imports) |
| `custom-ui-style.preferRestart` | `false` | Prefer restart over reload after updates (forced on for VS Code ≥ 1.95) |
| `custom-ui-style.reloadWithoutPrompting` | `false` | Reload/restart without a notification prompt |
| `custom-ui-style.webview.enable` | `true` | Apply style patching in webviews |
| `custom-ui-style.webview.removeCSP` | `true` | Remove CSP restrictions in webviews |
| `custom-ui-style.webview.stylesheet` | `{}` | Custom CSS for webviews; nested selectors |
| `custom-ui-style.webview.monospaceSelector` | `[]` | Custom monospace selectors for webviews |
| `custom-ui-style.webview.sansSerifSelector` | `[]` | Custom sans-serif selectors for webviews |
| `custom-ui-style.external.imports` | `[]` | External CSS/JS resources; supports variables + protocols |
| `custom-ui-style.external.loadStrategy` | `"refetch"` | `refetch` / `cache` / `disable` |
| `custom-ui-style.extensions.enable` | `true` | Enable file patching in other extensions |
| `custom-ui-style.extensions.config` | `{}` | Per-extension patch configs (key: extension ID) |
| `custom-ui-style.agents.stylesheet` | `{}` | Custom CSS for the Agents window |

26 settings total.

No keybindings.

---

## Editor utilities

### `editorconfig.editorconfig` — EditorConfig · 0.18.2

[Open VSX](https://open-vsx.org/extension/editorconfig/editorconfig) · [GitHub](https://github.com/editorconfig/editorconfig-vscode)

Reads `.editorconfig` files and applies the supported properties
(`indent_style`, `indent_size`, `tab_width`, `end_of_line`,
`insert_final_newline`, `trim_trailing_whitespace`, `charset`) to the editor.

**Usage:** nothing to configure — drop a `.editorconfig` in the project root.
Right-click a folder in the Explorer → **Generate .editorconfig** to create
one from your current editor settings.

**Known issue:** `trim_trailing_whitespace = false` is ignored while
`files.trimTrailingWhitespace` is `true` (this repo sets it to `true`, so
`.editorconfig` cannot re-enable trailing whitespace).

**Commands:** `EditorConfig.generate`

**Settings:**

| Setting | Default | Description |
| --- | --- | --- |
| `editorconfig.generateAuto` | `true` | Auto-generate `.editorconfig` from current editor settings |
| `editorconfig.template` | `"default"` | Template path used when `generateAuto` is `false` |
| `editorconfig.showMenuEntry` | `true` | Show "Generate .editorconfig" in the Explorer context menu |

No keybindings.

---

### `jasonlhy.hungry-delete` — Hungry Delete · 1.7.0

[Open VSX](https://open-vsx.org/extension/jasonlhy/hungry-delete) · [GitHub](https://github.com/Jasonlhy/VSCode-Hungry-Delete)

Deletes whole blocks of leading whitespace in one press. Two features:

1. **Hungry Delete** — `Ctrl+Backspace` (Mac: `Alt+Backspace`) removes all
   leading whitespace/tabs before the cursor up to the first non-empty char.
   Works with multiple cursors.
2. **Smart Backspace** — pressing `Backspace` deletes the empty line above or
   all whitespace to the end of the previous line.

**Commands:** `extension.hungryDelete`, `extension.smartBackspace`

**Keybindings:** `Ctrl+Backspace` → hungry delete; `Backspace` → smart
backspace (when enabled, editor focused, not readonly).

**Settings:**

| Setting | Default | Description |
| --- | --- | --- |
| `hungryDelete.enableSmartBackspace` | `true` | Enable Smart Backspace |
| `hungryDelete.keepOneSpace` | `false` | Keep one space after the previous line's last word |
| `hungryDelete.keepOneSpaceException` | `""` | Chars that disable keep-one-space |
| `hungryDelete.considerIncreaseIndentPattern` | `false` | Use the language's `increaseIndentPattern` for smart backspace |
| `hungryDelete.followAboveLineIndent` | `false` | Follow the indentation of the line above |

Built-in language configs for HTML, Go, JSON, Less, Lua, PHP, Ruby,
TypeScript, YAML. Can conflict with the Vim extension — the README documents
a `keybindings.json` workaround.

---

### `cardinal90.multi-cursor-case-preserve` — Multiple Cursor Case Preserver · 1.0.5

[Open VSX](https://open-vsx.org/extension/cardinal90/multi-cursor-case-preserve) · [GitHub](https://github.com/Cardinal90/multi-cursor-case-preserve)

Preserves the case of each word when typing with multiple cursors (e.g.
`user_id`, `userId`, `UserId` all stay in their own case while you type the
same text).

**Usage:** nothing to configure — activates automatically on multi-cursor
editing. No commands, keybindings, or settings.

---

### `arthurlobo.easy-codesnap` — Easy CodeSnap · 1.37.5

[Open VSX](https://open-vsx.org/extension/arthurlobo/easy-codesnap) · [GitHub](https://github.com/ArthurLobopro/easy-codesnap)

Beautiful, customizable code screenshots (CodeSnap fork).

**Usage:** select code → **Easy CodeSnap: Snap** (Command Palette, or
right-click the selection). A preview opens; tweak and copy/save.

**Commands:** `easy-codesnap.snap`, `easy-codesnap.openSettings`,
`easy-codesnap.importSettings`

**Key settings:**

| Setting | Default | Description |
| --- | --- | --- |
| `easy-codesnap.showLineNumbers` | `true` | Show line numbers |
| `easy-codesnap.saveFormat` | `"png"` | `png`, `svg`, or `webp` |
| `easy-codesnap.saveScale` | `1` | Output scale: 0.5 / 0.75 / 1 / 1.5 / 2 / 3 / 4 |
| `easy-codesnap.target` | `"container"` | `container` or `window` frame |
| `easy-codesnap.windowStyle` | `"macos"` | `macos` or `windows` window controls |
| `easy-codesnap.roundedCorners` | `true` | Rounded screenshot corners |
| `easy-codesnap.backgroundColor` | `"#abb8c3"` | Background color |
| `easy-codesnap.transparentBackground` | `false` | Transparent background |
| `easy-codesnap.shutterAction` | `"copy"` | What opening the shutter does: `copy` or `save` |
| `easy-codesnap.watermark` | `false` | Add watermark text |
| `easy-codesnap.aspect-ratio` | `"none"` | Force an aspect ratio (1:1, 16:9, …) |

35 settings total.

No keybindings.

---

## Editor niceties

### `aaron-bond.better-comments` — Better Comments · 3.0.2

[Open VSX](https://open-vsx.org/extension/aaron-bond/better-comments) · [GitHub](https://github.com/aaron-bond/better-comments)

Colorizes comments by tag prefix (60+ languages):

| Tag | Color | Meaning |
| --- | --- | --- |
| `// !` | red | Alerts |
| `// ?` | blue | Queries |
| `// //` | gray strikethrough | Commented-out code |
| `// todo` | orange | TODOs |
| `// *` | green | Highlights |

**Usage:** just write the tag — comments auto-colorize. No commands or
keybindings.

**Settings:**

| Setting | Default | Description |
| --- | --- | --- |
| `better-comments.multilineComments` | `true` | Highlight multiline comments |
| `better-comments.highlightPlainText` | `false` | Highlight in plain-text files |
| `better-comments.tags` | 5 default tags | Tag → color/style objects (bold, italic, underline, strikethrough, backgroundColor) |

⚠️ Tag changes require an editor restart.

---

## Git

### `codezombiech.gitignore` — gitignore · 0.10.0

[Open VSX](https://open-vsx.org/extension/codezombiech/gitignore) · [GitHub](https://github.com/CodeZombieCH/vscode-gitignore)

Pulls `.gitignore` templates from the official
[github/gitignore](https://github.com/github/gitignore) repo, plus syntax
highlighting for `.gitignore` files.

**Usage:** Command Palette → **Add gitignore** → pick a template. The
template list is cached to respect GitHub API rate limits.

**Commands:** `gitignore.addgitignore`

**Settings:**

| Setting | Default | Description |
| --- | --- | --- |
| `gitignore.cacheExpirationInterval` | `3600` | Seconds the template list is cached |

No keybindings.

---

## Zed (`zed/extensions.json`)

IDs live on the [Zed extension registry](https://zed.dev/extensions)
(mirrored at [zed-industries/extensions](https://github.com/zed-industries/extensions)).
Format constraint: each ID sits alone on its line — the file is parsed
line-based, so no trailing comments.

### `catppuccin-icons` — Catppuccin Icons

File icon theme in the four Catppuccin flavors (Latte, Frappe, Macchiato,
Mocha). Activate via Command Palette → `icon theme: select` after install.

### `emmet` — Emmet

HTML/CSS abbreviation expansion (`div.class>span` + Tab). Works in HTML, CSS,
JSX-adjacent scopes. No settings required.

### `git-firefly` — Git Firefly

Git integration inside Zed: inline blame, hunk staging/unstaging from the
editor, branch and commit helpers. Complements Zed's built-in git panel.

---

*Verified 2026-08 against the Open VSX registry and the Zed extension
registry. Install by ID so versions track the marketplace.*