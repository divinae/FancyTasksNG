# Taskline

A task manager for the Plasma 6 panel: icons or labeled buttons for your pinned apps and open
windows, with live window previews, media controls on the window that's actually playing,
unread badges, and attention signals that tell you which window wants you without getting in
your way.

Taskline is a fork of [Fancy Tasks NG](https://github.com/daydve/FancyTasksNG) by Vitaliy Elin.
It has its own name and widget ID (`io.github.divinae.taskline`), so the two can be installed
side by side.

## What it does

### On the panel

- **Pinned apps and windows** in one row, as icons or labeled buttons, aligned to the start or
  the center of the panel. Windows of one app can be grouped, always or only when the panel runs
  out of room. Pinned apps stay in their slots, also after Plasma restarts.
- **Indicators** under each task: lines or dots, one per window, in the accent color, the icon's
  color, the theme's text color (dark on light themes, light on dark ones) or a color of your
  choice, with an optional outline. The focused window's segment can be longer and its opacity
  set on its own; a minimized window's segment is greyed out.
- **Badges:** unread counts from apps that send notifications, or that report a count
  themselves (Unity LauncherEntry), the number of open windows, and a progress bar for downloads
  and copies, in the theme's accent color.
- **Audio:** a speaker on an app that's playing; scroll on it for its volume, click it to mute.
- **Launch feedback:** an app's icon bounces while it starts, as in the macOS Dock.

### Tooltips

Hover a task for a tooltip in the Plasma theme's own frame, with:

- **Previews** of its windows, sized to each window's shape when there are several, smoothly
  scaled and with rounded corners. Minimized windows are dimmed and marked.
- **Titles under the previews.** In a group, the part that differs between the windows is in
  bold and what they share is dimmed: **build** : bash, **docs** : bash.
- **Media controls** (play, pause, skip, seek, volume) on the window that's actually playing,
  including browser web apps: music playing in a Spotify app run by Vivaldi shows on the Spotify
  window, not on the browser's main window.
- A close button on hover, and optionally the most recently used window first. The delay before
  the tooltip opens is up to you.

### Attention

When a window asks for attention, as on the Windows taskbar: its icon bounces and its indicator
and button turn the attention color for 30 seconds, then only a steady colored mark stays, with
one reminder bounce every 5 minutes. A new message starts it again. In a group, only the window
that asked is marked, in the indicator and in the tooltip.

With an auto-hidden panel, Taskline can leave the panel hidden and let just that app's icon
bounce out of the screen edge where it sits (Settings › Advanced). Click it to go to the window.

### The context menu

Besides the usual window and pinning actions: the app's own actions (jump list), recent
documents and folders, recent pages for browsers, Places for file managers, **Close Other
Windows**, **Open at Login**, and **Force Quit** for an app that stopped responding.

### Keys and mouse

Meta+1…9 activate the task in that position, Meta+Shift+1…9 open a new window of it.
Ctrl+Shift+arrows move the focused task. Scroll, middle-click and Ctrl+scroll actions can be
set in the settings. Drop files on a task to open them with that app.

## Requirements

- Plasma 6.5 or later.
- `python3` with **dbus-python** and **PyGObject** (Arch: `python-dbus`, `python-gobject`;
  Debian/Ubuntu: `python3-dbus`, `python3-gi`; Fedora: `python3-dbus`, `python3-gobject`).
  Taskline runs two small helpers with them for jump lists, recent documents, badges, browser
  history and config export/import. Without them, those features are missing and the Advanced
  settings page says why.
- For media in browsers: the Plasma Browser Integration extension.

## Install

```sh
git clone https://github.com/divinae/Taskline.git
cd Taskline
make install
```

Then right-click the panel, **Add Widgets…**, and add **Taskline**. Coming from Fancy Tasks NG?
Export your settings there (Settings › Advanced) and import them in Taskline.

To update: `git pull && make update` (this restarts plasmashell). To remove: delete the widget
from your panels, then `make uninstall`.

## Development

`make preview` opens the widget in a window, `make test` runs the unit tests of the Python
helper, `make lint` runs ruff, shellcheck and the settings check, `make diag` writes a report
for bug reports (`taskline-diag.txt`). The changes since the fork are in the
[CHANGELOG](CHANGELOG.md).

## When something's off

- **No jump lists, recent documents or badges:** the Python helpers aren't running. Check the
  Advanced settings page and `make diag` for the missing module.
- **Media controls on the wrong browser window:** a browser doesn't say which tab plays, so
  Taskline goes by the window title and, for web apps, by the site. While a web app and a normal
  tab play at the same time, the sound counts for the web app.
- **The bouncing icon doesn't appear at the screen edge:** it only shows for auto-hidden panels,
  and not while a window is fullscreen.

## Credits

Taskline builds on the work of:

- [Vitaliy Elin](https://github.com/daydve): Fancy Tasks NG, the Plasma 6 rewrite this is
  forked from.
- [SushiTrashXD](https://github.com/SushiTrashXD): FancyTasksPlus, the first Plasma 6 port.
- [Alexandra Stone](https://github.com/alexankitty): the original FancyTasks for Plasma 5.
- [Luis Bocanegra](https://github.com/luisbocanegra): the hover zoom.
- The KDE task manager, which all of them started from.

## License

GPL-3.0-or-later.
