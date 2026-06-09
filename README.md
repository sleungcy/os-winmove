# winmove

Move and resize macOS windows with keyboard modifiers + mouse, without clicking the title bar.

## Usage

Hold a modifier combo while moving the mouse anywhere over a window:

| Modifier | Action |
|----------|--------|
| `Ctrl + Option` | Move window |
| `Option + Cmd` | Resize window (from bottom-right) |

Works with all apps including Firefox, terminals, and Electron apps.

## Requirements

- macOS (tested on Ventura/Sonoma/Sequoia)
- Accessibility permission (prompted on first run)

## Install

```bash
make build
make install   # copies binary to /usr/local/bin
```

Or run directly without installing:

```bash
make run
```

## Autostart (Login Item)

```bash
make load    # registers as a launchd user agent (starts on login)
make unload  # removes the login item
make status  # check if the agent is running
```

## Debug

```bash
make debug   # runs with -debug flag (prints events to stdout)
```

## Permissions

On first run, macOS will prompt for Accessibility access. Grant it in:

**System Settings → Privacy & Security → Accessibility**

Then run again. The permission is remembered across sessions.
