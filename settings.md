# Settings — explained reference

> Every setting from `settings.jsonc` (merged snapshots), what it does, and the values it accepts.
> Current value = the `[current]`-era value. Generated 2026-08-14.

## Workbench & Window

| Setting | Current | What it does | Other values |
|---|---|---|---|
| `window.commandCenter` | `false` | Show the Command Center (search box + run command) in the title bar | `true` |
| `workbench.layoutControl.enabled` | `false` | Show the layout control icons (panels toggle) in the title bar | `true` |
| `window.zoomLevel` | `1` | Zoom the whole UI (font-size independent) | `0`, `-1`, `2`… (can be fractional) |
| `workbench.colorTheme` | `"Vercel Dark"` | Color theme id | Any installed theme id (e.g. `"Tokyo Night"`, `"Aura Dracula Spirit (Soft)"`) |
| `workbench.iconTheme` | `"charmed-icons"` | File/folder icon theme id | `"symbols"`, `"material-icon-theme"`, `null` (none) |
| `workbench.productIconTheme` | `"fluent-icons"` | Icon theme for VS Code's *own* UI icons (widgets, actions) | `null` (built-in set) |
| `workbench.activityBar.location` | `"hidden"` | Where the Activity Bar (left icon rail) sits | `"left"`, `"top"`, `"bottom"`, `"hidden"` |
| `workbench.statusBar.visible` | `false` | Show the status bar at the bottom | `true` |
| `window.menuBarVisibility` | `"toggle"` | Menu bar visibility | `"default"`, `"visible"`, `"hidden"`, `"compact"` |
| `workbench.startupEditor` | `"newUntitledFile"` | What to show on startup | `"none"`, `"welcomePage"`, `"readme"`, `"welcomePageInEmptyWorkbench"` |
| `workbench.editor.showTabs` | `"single"` | How editor tabs behave | `"multiple"`, `"single"` (one at a time), `"none"` (tabless) |
| `workbench.editor.labelFormat` | `"short"` | Tab label content | `"medium"` (dir), `"long"` (full path) |
| `workbench.editor.enablePreview` | `false` | Open files in preview tabs (reused until edited) | `true` |
| `workbench.editor.empty.hint` | `"hidden"` | Hint shown in empty editors | `"text"` (shows "No editors open" hint) |
| `workbench.browser.showInTitleBar` | `false` | Show native browser title bar (web/remote) | `true` |
| `workbench.list.smoothScrolling` | `true` | Smooth-scroll lists/trees | `false` |
| `workbench.tree.enableStickyScroll` | `false` | Pin parent rows at top when scrolling trees | `true` |
| `workbench.tree.renderIndentGuides` | `"none"` | Indent guide lines in trees | `"onHover"`, `"always"` |
| `workbench.tree.indent` | `8` | Tree indent width in px | Any number |
| `breadcrumbs.enabled` | `false` | Breadcrumb trail above the editor | `true` |

## Editor

| Setting | Current | What it does | Other values |
|---|---|---|---|
| `editor.fontFamily` | `"DankMono Nerd Font"` | Font stack (comma-separated fallbacks) | Any installed font |
| `editor.fontSize` | `16` | Font size in px | Any number |
| `editor.fontLigatures` | `true` | Enable ligatures | `false`, or a feature string like `"'ss01','cv01'"` |
| `editor.lineHeight` | `2` | Line height in px (`0` = auto from font size) | `0`, ~`24`–`32` typical for 16px font |
| `editor.tabSize` | `2` | Tab width in spaces | Any number |
| `editor.insertSpaces` | `true` | Use spaces for indentation | `false` (tabs) |
| `editor.detectIndentation` | `false` | Auto-detect indentation from file content | `true` |
| `editor.wordWrap` | `"wordWrapColumn"` | Wrap behavior | `"off"`, `"on"` (viewport), `"wordWrapColumn"`, `"bounded"` |
| `editor.wordWrapColumn` | `140` | Column used by `wordWrapColumn`/`bounded` | Any number |
| `editor.rulers` | `[140]` | Vertical guide lines at columns | `[]`, `[80, 120]`, … |
| `editor.formatOnSave` | `true` | Format when saving | `false` |
| `editor.formatOnType` | `true` | Format while typing (after lines) | `false` |
| `editor.formatOnPaste` | `true` | Format pasted content | `false` |
| `editor.defaultFormatter` | `"biomejs.biome"` | Formatter extension id | `null`, `"esbenp.prettier-vscode"`, … |
| `editor.renderControlCharacters` | `false` | Show control characters (e.g. `↵`) | `true` |
| `editor.renderWhitespace` | `"trailing"` | When to render whitespace glyphs | `"none"`, `"boundary"`, `"selection"`, `"trailing"`, `"all"` |
| `editor.glyphMargin` | `false` | Margin column for icons (breakpoints, etc.) | `true` |
| `editor.minimap.enabled` | `false` | Minimap on the right | `true` |
| `editor.linkedEditing` | `true` | Edit matching HTML/JSX tag pairs together | `false` |
| `editor.mouseWheelZoom` | `true` | `Ctrl+wheel` zooms font | `false` |
| `editor.mouseWheelScrollSensitivity` | `2` | Wheel scroll speed multiplier | `1` (default), any number |
| `editor.smoothScrolling` | `true` | Smooth editor scrolling | `false` |
| `editor.cursorStyle` | `"line"` | Cursor shape | `"block"`, `"underline"`, `"line-thin"`, `"block-outline"`, `"underline-thin"` |
| `editor.cursorBlinking` | `"expand"` | Cursor blink animation | `"blink"`, `"smooth"`, `"phase"`, `"solid"` |
| `editor.cursorWidth` | `2` | Cursor width in px (line style) | Any number |
| `editor.cursorSmoothCaretAnimation` | `"on"` | Animate cursor movement | `"off"`, `"explicit"` |
| `editor.snippetSuggestions` | `"bottom"` | Where snippets appear in suggestions | `"top"`, `"inline"`, `"none"` |
| `editor.suggestSelection` | `"first"` | Which suggestion is pre-selected | `"recentlyUsed"`, `"recentlyUsedByPrefix"` |
| `editor.suggest.localityBonus` | `true` | Prioritize words near cursor in suggestions | `false` |
| `editor.wordBasedSuggestions` | `"off"` | Suggest words from open documents | `"currentDocument"`, `"matchingDocuments"`, `"allDocuments"` |
| `editor.acceptSuggestionOnCommitCharacter` | `false` | Accept suggestions on chars like `.` `(` | `true` |
| `editor.renderLineHighlight` | `"all"` | Highlight current line | `"none"`, `"gutter"`, `"line"` |
| `editor.guides.bracketPairs` | `false` | Bracket pair guides | `true`, `"active"` (only active pair) |
| `editor.guides.indentation` | `false` | Indentation guides | `true` |
| `editor.bracketPairColorization.enabled` | `true` | Colorize matching brackets | `false` |
| `editor.bracketPairColorization.independentColorPoolPerBracketType` | `true` | Separate color pools per bracket type (`()[]{}`) | `false` |
| `editor.scrollbar.horizontal` | `"hidden"` | Horizontal scrollbar | `"auto"`, `"visible"`, `"hidden"` |
| `editor.accessibilitySupport` | `"off"` | Optimize for screen readers | `"auto"`, `"on"` |
| `editor.hover.enabled` | `"on"` | Show hover on hover | `false` |
| `editor.hover.delay` | `1500` | Hover delay in ms | Any number |
| `editor.inlineSuggest.enabled` | `true` | Show inline (ghost-text) suggestions | `false` |
| `editor.tokenColorCustomizations` | `{textMateRules…}` | Override theme colors/font styles (here: comments → italic) | `{}` |

## Explorer & Files

| Setting | Current | What it does | Other values |
|---|---|---|---|
| `explorer.confirmDelete` | `false` | Ask before deleting files | `true` |
| `explorer.compactFolders` | `false` | Collapse single-child folder chains in explorer | `true` |
| `explorer.confirmDragAndDrop` | `false` | Ask before drag-and-drop moves | `true` |
| `files.autoSave` | `"afterDelay"` | Auto-save behavior | `"off"`, `"onFocusChange"`, `"onWindowChange"` |
| `files.insertFinalNewline` | `true` | Ensure file ends with newline on save | `false` |
| `files.trimTrailingWhitespace` | `true` | Strip trailing whitespace on save | `false` |
| `files.defaultLanguage` | `"{activeEditorLanguage}"` | Language for new untitled files | Any language id (e.g. `"markdown"`) |
| `files.associations` | `css→tailwindcss`, `cshtml→html`, `appsettings*.json→jsonc` | Force language for file patterns | Any glob → language map |

## Git

| Setting | Current | What it does | Other values |
|---|---|---|---|
| `git.enableSmartCommit` | `true` | Commit all staged changes with no message prompt | `false` |
| `git.autofetch` | `true` | Auto-fetch remotes periodically | `false` |
| `git.confirmSync` | `false` | Skip confirm dialog on sync (pull+push) | `true` |
| `js/ts.updateImportsOnFileMove.enabled` | `"always"` | Update import paths when JS/TS files move | `"prompt"`, `"never"` |

## Terminal

| Setting | Current | What it does | Other values |
|---|---|---|---|
| `terminal.integrated.defaultProfile.windows` | `"Git Bash"` | Default shell profile on Windows | `"PowerShell"`, `"Command Prompt"`, … |
| `terminal.integrated.fontFamily` | `"DankMono Nerd Font"` | Terminal font | Any installed font |
| `terminal.integrated.cursorStyle` | `"line"` | Terminal cursor shape | `"block"`, `"underline"` |
| `terminal.integrated.cursorStyleInactive` | `"underline"` | Cursor when terminal not focused | `"none"`, `"line"`, `"block"`, `"outline"` |
| `terminal.integrated.env.windows` | `{}` | Extra env vars for Windows terminals | `{"KEY": "value"}` |

## Security & Telemetry

| Setting | Current | What it does | Other values |
|---|---|---|---|
| `security.workspace.trust.untrustedFiles` | `"open"` | How to handle untrusted files in trusted workspaces | `"prompt"`, `"newWindow"` |
| `security.promptForLocalFileProtocolHandling` | `false` | Ask before opening `file://` links | `true` |
| `telemetry.telemetryLevel` | `"off"` | Telemetry level | `"crash"`, `"error"`, `"all"` |
| `json.schemaDownload.trustedDomains` | 8 domains | Domains allowed to provide JSON schemas | Add/remove domains |
| `diffEditor.ignoreTrimWhitespace` | `false` | Show whitespace-only changes in diffs | `true` |

## Chat / AI

| Setting | Current | What it does | Other values |
|---|---|---|---|
| `chat.titleBar.signIn.enabled` | `false` | Sign-in button in title bar | `true` |
| `chat.titleBar.openInAgentsWindow.enabled` | `false` | "Open in Agents window" button in title bar | `true` |
| `chat.viewSessions.orientation` | `"stacked"` | Chat session history layout | `"list"` (side-by-side) |

## Language-specific

| Setting | Current | What it does | Other values |
|---|---|---|---|
| `[xml]` → `editor.defaultFormatter` | `"biomejs.biome"` | Formatter override for XML files | Any formatter id |
| `biome.suggestInstallingGlobally` | `false` | Stop Biome suggesting a global install | `true` |

## custom-ui-style (extension)

| Setting | Current | What it does | Other values |
|---|---|---|---|
| `custom-ui-style.font.sansSerif` | `"DankMono Nerd Font"` | UI sans-serif font override | Any font |
| `custom-ui-style.electron.titleBarStyle` | `"hiddenInset"` | Electron title bar style (macOS-style inset) | `"hidden"`, `"default"` |
| `custom-ui-style.stylesheet` | 19 CSS rules | Inject raw CSS into the VS Code UI (kills shadows/scrollbars, centers file icons) | Any CSS property map |

## Legacy (in `settings.jsonc` but not `[current]`)

| Setting | Era | Note |
|---|---|---|
| `codeium.enableConfig` | 2023 | Codeium AI toggle — replaced by Copilot |
| `cSpell.*` | 2023 | Spell-checker config + custom dictionary path |
| `colorize.*` | 2023 | Color preview extension config |
| `editor.stickyScroll.enabled` | 2025-04 | Replaced by `workbench.tree.enableStickyScroll` |
| `editor.quickSuggestions` | 2025-04 | Per-context suggestion on/off |
| `editor.tabCompletion` | 2025-04 | `Tab` completes suggestions |
| `editor.codeLens` / `editor.links` / `editor.colorDecorators` | 2025 | Hide code lens, clickable links, color decorators |
| `editor.occurrencesHighlight` / `selectionHighlight` | 2025 | Disable word-occurrence highlights |
| `editor.overviewRulerBorder` / `hideCursorInOverviewRuler` | 2025 | Slim the overview ruler |
| `editor.scrollbar.vertical` | 2025-04 | Hide vertical scrollbar |
| `editor.colorCustomizations` | 2025-04 | Aura-theme-specific color tweaks |
| `editor.lineNumbers` (commented) | 2025-04 | `"off"` — hidden line numbers |
| `emmet.triggerExpansionOnTab` | 2025-04 | Emmet expands on Tab |
| `editor.codeActionsOnSave` | 2025-10 | Biome fix-all + organize imports on save |
| `symbols.hidesExplorerArrows` | 2025 | Symbols theme: no explorer arrows |
| `extensions.ignoreRecommendations` | 2025-04 | Suppress extension recommendation popups |
| `update.mode` | 2025-04 | `"none"` — disable auto-update |
| `license.default` / `license.author` | 2025-04 | choosealicense extension defaults |
| `geminicodeassist.project` | 2025-04 | Gemini Code Assist project |
| `auto-close-tag.disableOnLanguage` | 2025-04 | Auto-close-tag off for TS/TSX |
| `prettier.*` | 2025-04 | Prettier options (superseded by Biome) |
| `terminal.integrated.cursorBlinking` | 2025-10 | Blinking terminal cursor |
| `chat.commandCenter.enabled` | 2025-10 | Hide chat command center |
| `security.allowedUNCHosts` | 2025-04 | Trust `wsl.localhost` UNC hosts |
| `scm.diffDecorations` | 2025 | No diff decorations in source control |
| `workbench.tips.enabled` | 2025 | Suppress tips |
| `explorer.decorations.badges` / `git.decorations.enabled` | 2025 | Strip explorer/git badges |