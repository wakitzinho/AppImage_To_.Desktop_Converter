# appimage-desktop.sh

Converts an AppImage into a `.desktop` entry so it shows up in your app launcher.

## Usage

```bash
chmod +x appimage-desktop.sh
./appimage-desktop.sh /path/to/App.AppImage
```

## What it does

- Makes the AppImage executable if it isn't already
- Extracts the AppImage and searches for an icon in this order:
  1. `.DirIcon` at the AppImage root (the standard AppImage icon)
  2. Highest-res `.png` under `usr/share/icons/` inside the AppImage
  3. Any `.png` at the AppImage root
  4. `.svg` fallback, then `.xpm`
  5. Any image in the same folder as the AppImage
- If an icon is found, copies it to `~/.local/share/icons/`
- Reads metadata (`Name`, `Comment`, `Categories`) from the AppImage's own `.desktop` file if one exists
- Writes a `.desktop` entry to `~/.local/share/applications/`
- Runs `update-desktop-database` so the launcher picks it up immediately

If no icon is found, the entry is still created — just without an `Icon=` field.


Needs to be a Type 2 AppImage (anything made after ~2017 should be fine)

## Output locations

| File          | Path                                            |
| ------------- | ----------------------------------------------- |
| Desktop entry | `~/.local/share/applications/<AppName>.desktop` |
| Icon          | `~/.local/share/icons/<AppName>.<ext>`          |

## Notes

- If the app doesn't appear in your launcher right away, try logging out and back in or running `update-desktop-database ~/.local/share/applications` manually.
- The original AppImage is not moved or modified (aside from being made executable).
