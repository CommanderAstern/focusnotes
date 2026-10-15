# focusnotes

**Take notes without breaking focus.**

focusnotes is a small macOS menu-bar app for capturing what you're reading or thinking without leaving the app you're
working in. Select text and press a shortcut. Drag over part of the screen. Jot a quick note in a floating panel. Your
window keeps focus the whole time, and everything lands in plain Markdown files you own.

> **Status:** early and in active testing. There is no `.dmg` yet; build it from source using the steps below.

## Why

Taking a note usually means a context switch: open the notes app, find the right page, paste, tidy up, switch back.
Each switch costs a little attention, and you lose more of it the more often you do it.

focusnotes never pulls you out of what you're doing:

- **No app switching.** Captures happen in place. focusnotes never activates itself or steals focus from your window.
- **Keyboard first.** Every action has a global shortcut, and a toast confirms it was saved.
- **Sessions.** Start a session for a topic, such as a course, a paper or a design review, and every capture and
  note goes to that topic's note until you end it.
- **Plain Markdown.** Notes are ordinary `.md` files, compatible with Obsidian or any editor. There's no database
  you can't read and no lock-in.
- **On-device.** Captured text, screenshots, OCR, keyword search and optional
  semantic search run on your Mac. The app does not upload note content.
  Installing optional semantic models is an explicit download from Hugging Face
  and GitHub; see [semantic search](docs/semantic-search.md).

## Features

- **Capture selection.** Saves the selected text from any app, along with where it came from.
- **Capture area.** Drag over part of the screen to save it as an image. Text in the image is recognised (OCR) and
  becomes searchable.
- **Quick note.** A floating panel for typing Markdown with a live preview. It stays on screen while you work in
  other windows, and saves with ⌘↩.
- **Search.** Keyword search across all your notes, plus optional on-device semantic search.
- **Sessions and subheadings.** Group captures by topic, and add a subheading to start a new section.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| <kbd>⌥⇧C</kbd> | Capture selected text |
| <kbd>⌥⇧S</kbd> | Capture an area of the screen |
| <kbd>⌥⇧N</kbd> | Write a quick note |
| <kbd>⌥⇧F</kbd> | Search notes |
| <kbd>⌥⇧A</kbd> | Start or end a session |
| <kbd>⌥⇧H</kbd> | Add a subheading |
| <kbd>⌥⇧L</kbd> | Open the notes folder |

Inside the quick note: <kbd>⌘↩</kbd> saves, <kbd>⌘K</kbd> opens actions, <kbd>⌘P</kbd> browses notes, <kbd>esc</kbd>
closes it and keeps your draft.

## Getting started

### Requirements

- macOS 14 Sonoma or later
- A Swift 6.4 toolchain: a current Xcode, or the Command Line Tools
- Python 3 for the bundle build, plus the macOS command-line tools used by the
  scripts (`plutil`, `codesign`, `ditto`, `open`)
- Apple silicon, only if you want semantic search

### Build and run

```bash
git clone https://github.com/zerodoxxx/focusnotes.git
cd focusnotes
./scripts/run-app.sh
```

`run-app.sh` builds the app, quits any running copy, replaces the installed copy
at `/Applications/focusnotes.app` (or `~/Applications` if `/Applications` is not
writable) and opens it. It then deletes the build artifacts (`.build` and
the staged bundle), which can take several GB; set `KEEP_BUILD=1` to keep them for faster incremental rebuilds. A tray
icon appears in the menu bar; there is no Dock icon. Use `./scripts/run-app.sh release` for an optimised build. To
build without installing or launching, run `./scripts/build-app.sh`.

### Grant permissions

On first use, macOS asks for two permissions. Grant them in **System Settings → Privacy & Security**:

| Permission | Needed for |
| --- | --- |
| Accessibility | Reading the selected text in other apps |
| Screen Recording | Capturing an area of the screen |

The menu-bar menu shows the status of each under **Permissions**.

> **Tip:** local builds are signed ad hoc by default, so macOS may ask for permissions again after a rebuild. To use
> your own signing identity, pass it explicitly: `SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/run-app.sh`.

### Optional: semantic search

Keyword search works out of the box. For semantic (meaning-based) search, download the on-device models (about 500 MB,
Apple silicon):

```bash
./scripts/fetch-models.sh "$HOME/Library/Application Support/com.zerodoxxx.focusnotes/models"
```

Restart the app afterwards. The menu shows **Semantic search: On** once the models are found. See
[docs/semantic-search.md](docs/semantic-search.md) for details.

## Where your notes live

Notes are saved in `~/Documents/focusnotes`:

```text
focusnotes/
├── Inbox.md              # captures made outside a session
├── Sessions/
│   └── System Design.md  # one note per session
├── <Quick note title>.md # quick notes written outside a session
└── assets/               # area captures (images)
```

Each note is readable Markdown. Timestamps and source details live in invisible HTML comments, so the text itself stays
clean:

```markdown
# System Design

### Designing Data-Intensive Applications
<!-- capture:… at=2026-10-14T13:04:58+05:30 app="Firefox" -->

Replication lag is the delay between a write on the leader and its visibility on followers.
```

To keep notes somewhere else, such as an Obsidian vault, set the folder and restart the app:

```bash
defaults write com.zerodoxxx.focusnotes vaultPath "~/Obsidian/Notes"
```

App state (drafts, the search index and pending saves) lives in
`~/Library/Application Support/com.zerodoxxx.focusnotes`.

## License and contributing

Project-owned files are licensed under the OSI-approved [MIT License](LICENSE),
which permits commercial use subject to its terms and notice requirements.
Third-party code and downloaded model/runtime artifacts keep their separate
terms; see
[third-party notices](THIRD_PARTY_NOTICES.md). Contributions are covered by the
same project terms described in [CONTRIBUTING.md](CONTRIBUTING.md).

## Development

```bash
swift build                     # build every target
swift run CoreChecks            # storage, index and Markdown checks
swift run OverlayGallery --check   # UI behaviour checks for the panels
swift run OverlayGallery        # render UI snapshots to build/gallery/
scripts/check-name.sh           # make sure the app name lives only in Config/app.env
```

The app name, bundle prefix and version are set in `Config/app.env`; nothing else hard-codes them.

| Target | What it holds |
| --- | --- |
| `App` | The menu-bar app: shortcuts, capture flow, sessions, menu |
| `Core` | Headless logic: the Markdown vault, journaling, the SQLite FTS5 search index |
| `CaptureKit` | Global hotkeys, text selection and screen-area capture |
| `OverlayKit` | Panels: quick note, search, toasts, capture input |
| `EmbedKit` / `EmbedHelper` | The on-device embedding engine for semantic search |
| `OverlayGallery` | UI snapshots and behaviour checks for `OverlayKit` |

## Further reading

- [docs/reference.md](docs/reference.md): detailed capture, storage and editor behaviour
- [docs/quick-note-ui.md](docs/quick-note-ui.md): the quick-note panel's design
- [docs/demo.md](docs/demo.md): a full walkthrough and the self-test
- [docs/manual-tests.md](docs/manual-tests.md): manual test checklist
- [docs/semantic-search.md](docs/semantic-search.md): how semantic search works
- [docs/release-checklist.md](docs/release-checklist.md): current release review gates
- [SECURITY.md](SECURITY.md): vulnerability reporting and security scope
