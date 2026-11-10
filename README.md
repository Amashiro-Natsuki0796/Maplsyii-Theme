# i3 Everforest — one-shot installer for Debian 13

Reproduces the desktop from
[\[Sway\] - Everforest](https://plus.diolinux.com.br/t/sway-everforest/63254)
on a stock **Debian 13 (trixie)** install, driven by an English TUI.

The original rice was a **Sway/Wayland** desktop. This installer is the same
rice ported to **i3 on X11**: the theme, the icon set, the wallpaper, the
colours, the bar layout and every keybinding are unchanged, but the window
manager, the bar, the launcher, the notification daemon, the locker and every
helper behind a bar button speak X11 instead of Wayland.

| From the post | Installed here |
|---|---|
| Window manager **Sway** (Wayland) | **i3 4.24** (X11, i3-gaps merged upstream) |
| Bar **Waybar** | **i3-everforest-bar**, a GTK3 program that draws the *same* CSS |
| Launcher **Wofi** (440×330, 17px) | **Rofi 1.7**, same 440×330 geometry, 17px font, 41px rows, lime selection |
| Terminal **foot** (Wayland-only) | **st** with foot.ini's look ported: JetBrains Mono 14px, 2px border, `#000000` background, block cursor. Ships with 2000 lines of scrollback, mouse-wheel scrolling, a translucent scrollbar, Ctrl+click URLs, and is registered as the default terminal |
| Theme **Everforest-Dark-BL-LB** | GTK2/3/4 theme `Everforest-Dark-BL-LB` + libadwaita override |
| Icons **Material-Black-Lime-Numix-FLAT** | exact icon set, bundled (no network) |
| Notifications **mako** | **Dunst**, same Everforest palette and geometry |
| Lock screen **swaylock** | **i3lock** with the wallpaper and the Everforest palette |
| Wallpaper `wallhaven.cc/w/4xxw9z` | bundled 1920×1080 JPEG |
| Distro *Arch Linux* | **Debian 13** — the fetch block is rewritten for dpkg/apt |
| (greeter) | **SDDM + SilentSDDM theme**, so a bare install boots to a login screen |

Everything the look depends on is embedded in the installer, so it works
on a machine with no network at all.

---

## The Sway variant

`src/sway/` builds a second installer (`src/build-sway.sh` → `sway-setup.sh`)
for the same rice on Wayland. Most of the desktop is shared; the parts that
differ are the compositor, the terminal and the bar.

### The bar is a native Wayland C program, not Waybar

`assets/bar-sway/` is a cairo bar written against `wl_shm` and
`wlr-layer-shell`. It is a direct port of the X11 bar (`assets/bar-i3`): the same
drawing code, the same module order, the same palette.

It exists because **Waybar cannot draw the CPU sparkline**. A `custom` module
emits text, and a character cell cannot hold a 1.6px polyline — the closest
approximations (block glyphs, then braille dots) were both visibly wrong
against the i3 screenshot. Drawing into a shm buffer with cairo gives the exact
same 46×20 plot, including the filled area under the line and the 50% guide.

Measured on the same machine, same desktop:

| | Waybar | `i3-everforest-bar-wl` |
|---|---|---|
| PSS | 29 MB | **5.5 MB** |
| CPU | 0.5% | 0.7% |
| Link-time deps | 114 | 12 |

The CPU figure is slightly higher because the C bar redraws the graph at 15Hz
where Waybar polls once a second; it buys a line that actually moves.

### Why the X11 bar could not simply be reused

It calls `XGetImage(RootWindow(...))` to sample the wallpaper behind the panel.
Under XWayland that request fails with `BadMatch` — a Wayland compositor never
hands out root-window pixels — and the bar dies on startup. The Wayland version
has no such code at all: it paints with an alpha channel and lets the
compositor blend, which is both simpler and more correct.

### Terminal: foot, configured to match st

| | st (X11) | foot (Wayland) |
|---|---|---|
| Background | `ST_ALPHA=78` | `alpha=0.78` |
| Wheel scroll | one line per notch | `multiplier=1.0` |
| Links | underlined, clickable | always underlined, `Ctrl+Shift+o` |

foot has no scrollbar and no "open the link at this coordinate" action, so
those two st behaviours have no Wayland equivalent; everything else matches.

### Building the bar

The installer compiles it on the target, so it links against that machine's
libwayland/cairo/pango:

```bash
sudo apt install wayland-protocols libwayland-dev libxkbcommon-dev \
                 libcairo2-dev libpango1.0-dev
cd assets/bar-sway && make
```

There is **no Waybar fallback**: if the build fails the installer stops. A bar
is not optional, and silently swapping in a different one would hide the
failure behind a UI that looks almost right.

---

## Project layout

```
sway-everforest/
├── README.md
├── i3-setup.sh              built by src/build-i3.sh
├── sway-setup.sh            built by src/build-sway.sh
├── assets/                  everything both rices install
│   ├── bar-config/          i3 bar settings (bar.json)
│   ├── bar-i3/              X11 C bar sources
│   ├── bar-sway/            Wayland C bar sources
│   ├── tools/               standalone commands embedded into the installer
│   ├── fonts/  gtk-theme/  icons/  sddm/  st-patches/
│   ├── wallpaper.jpg
│   └── user-avatar.jpg
└── src/
    ├── build-i3.sh          assemble the i3 installer
    ├── build-sway.sh        assemble the sway installer
    ├── i3/                  i3 installer sections, in load order
    └── sway/                sway installer sections, in load order
```

The two rices share `assets/` but keep separate source directories, so each can
evolve without disturbing the other. Both build scripts anchor on the project
root, so they can be run from anywhere; the installer lands next to this README
and no build output is kept in the tree.


## Quick start

An interactive run opens with a three-way action menu:

```
  1  Install      install the components you pick
  2  Reinstall    re-select everything and install again
  3  Uninstall    remove everything this script installed
```

Pass `--yes`, `--uninstall` or `--dry-run` to skip that question entirely.

```sh
chmod +x i3-setup.sh
sudo ./i3-setup.sh
```

You get a numbered menu; type a number to toggle a component, then `i` to
install:

```
  [x] 1      Desktop core    i3, GTK bar, kitty, rofi, dunst, feh
       Required. X11 window manager, bar, terminal, launcher, notifications.
  [x] 2      Everyday apps   pcmanfm, btop, pavucontrol, flameshot, imv, mpv
  ...
  [x] 8      Shell extras    mf fetch block + Everforest bash prompt

  ────────────────────────────────────────────────────────────────────
  selected: 8/8

  1-8 toggle    a all    n none    i install    q quit
```

Afterwards: **reboot**. SDDM comes up with the SilentSDDM greeter; pick
**i3 (Everforest)** and you land in the desktop. From a TTY you can also run
`startx i3`.

### Non-interactive

```sh
sudo ./i3-setup.sh --yes                  # everything
sudo ./i3-setup.sh --only-dots --yes      # configs only
sudo ./i3-setup.sh --only-theme --yes     # theme + icons only
```

### Undo

```sh
sudo ./i3-setup.sh --uninstall --keep-packages
```

---

## Why X11, and what changed

Sway is a Wayland compositor; i3 is an X11 window manager. They share the
same configuration language and the same MOD-key workflow, which is why the
rice ports cleanly, but nothing that talked to the Wayland compositor works
unchanged. Each replacement keeps the *visual* contract of the original:

| Job | Wayland (before) | X11 (now) | Why |
|---|---|---|---|
| window manager | `sway` | `i3` | i3 is sway's direct ancestor: same `bindsym`, gaps, borders |
| bar | `waybar` (GTK + layer shell) | `i3-everforest-bar` (GTK + EWMH dock) | Waybar is itself GTK3, so the rice stylesheet is reused verbatim; only the layer-shell part is replaced by a dock window with a strut |
| launcher | `wofi` | `rofi` | wofi is GTK4 layer-shell, X11-incompatible; rofi is its X11 sibling |
| notifications | `mako` | `dunst` | mako is a Wayland client; dunst is the X11 daemon with the same knobs |
| locker | `swaylock` | `i3lock` | same author family, same palette via X resources |
| wallpaper | `swaybg` | `xwallpaper` | swaybg needs a Wayland output |
| screenshots | `grim` + `slurp` + `wl-copy` | `maim` + `slop` + `xclip` | Wayland screen-copy APIs have no X11 equivalent |
| idle / lock | `swayidle` | `xss-lock` + `xprintidle` | X screensaver extension + logind |
| compositor effects | sway (none) | `picom` (shadows, xrender) | the reference has no blur; picom supplies the shadows and per-window opacity |
| session entry | `/usr/share/wayland-sessions` | `/usr/share/xsessions` | X11 sessions live in `xsessions` |
| keyboard layout | `swaymsg input xkb_switch_layout` | `setxkbmap` | no compositor to ask |
| clipboard | `wl-copy` | `xclip` | X11 `CLIPBOARD` selection |

What did **not** change: the GTK theme, the icon theme, the wallpaper, the
palette, the bar layout, the keybindings, the `mf` fetch block, the bash
prompt, the power menu's actions, the SDDM greeter, and every file path under
`~/.config`.

`picom` is started from `~/.config/picom/picom.conf` with the `xrender`
backend, a soft shadow and an explicit exclusion for the bar: the reference has
no blur, so no blur is configured. The rules live in a config file rather than
on the command line because i3 does not honour shell quoting on an `exec` line
— a `shadow-exclude 'class_g = "Polybar"'` written inline reaches picom with
its quotes stripped and silently stops matching.

## Bar

The bar is **`i3-everforest-bar`**: ~2000 lines of C using cairo and Pango on a
plain X11 dock window. No GTK, no Python runtime, no toolkit event loop.
It began as a faithful port of the Waybar stylesheet the GTK version rendered,
then replaced it to cut its memory footprint by an order of magnitude and to
remove the class of stalls a managed toolkit event loop invites.

| | GTK version | C version |
|---|---|---|
| Memory (RSS) | 62-72 MB | **3-4 MB** |
| CPU (idle) | 2-3 % | **0.3 %** |
| Runtime deps | python3 + PyGObject + GTK3 | none (static ELF) |
| Binary | 1486-line script | **47 KB** |
| Stall risk | main loop can block on GC | none (no GC, no interpreter) |

### Layout

The module order is byte-for-byte the Waybar one:

```
left   : workspaces, separator, screenshot, ime
centre : window title
right  : sysinfo, launcher, notifications, power, clock, network
```

Geometry and palette match the reference exactly: 34 px strip, 6 px top margin,
8 px side margins, 12 px panel radius, 9 px pill radius, bar `#171b1c`, pill
`#2f3336`, text `#d3c6aa`, cream `#fffbef`, lime `#b9ff66`, launcher `#00ff00`,
notifications `#7c7aff`, power `#fa3433`, JetBrains Mono 14 px / 700.

Every constant carries the CSS rule it came from in `src/i3/config.h`, so a value
can be checked against the stylesheet without reading the drawing code.

### Transparency

Three presets live in `bar.json` (`"opacity"`):

| Level | Panel alpha | Use when |
|---|---|---|
| `solid` | 1.00 | maximum legibility |
| `soft` | 0.82 | a hint of wallpaper |
| `clear` | 0.35 | obvious see-through |

Change it at runtime:

```sh
i3-everforest-bar-opacity            # cycle solid -> soft -> clear
i3-everforest-bar-opacity clear      # set one preset
```

The helper rewrites `bar.json` and sends `SIGHUP`; the bar re-reads the file and
repaints, so no restart is needed and the choice survives the next login.
Reinstalling no longer resets it: `--opacity` is only applied when passed
explicitly.

The area outside the 12 px corner radius is genuinely transparent, so the
desktop shows through the rounded corners rather than a black box. The bar is
excluded from picom's blur, so its panel is always a plain translucent strip
and never a frosted one.

### Interaction

Every pill responds to the pointer:

* **hover** - a white veil at 18 % lifts the pill
* **press** - the same veil at 38 % while the button is held
* **tooltip** - an English description of what the pill does, shown under the
  bar after a short hover; it disappears the moment the pointer leaves the
  control, and stays hidden after a click until the pointer leaves and returns

The graph repaints at 30 Hz while the rest of the bar redraws only when
something changed, so motion stays smooth without burning CPU.

#### Why the CPU line scrolls evenly

The trace is a strip of samples that slides one step left every 250 ms. Two
details decide whether it looks smooth, and both are commented where they are
implemented:

* **The plot is clipped to its rectangle, and every point slides.** Without a
  clip the left end of the line is the oldest point itself, which marches out
  of the plot and snaps back on every sample - the hop at the tail. With the
  clip, both ends are clean cuts at the border.
* **The whole strip is rigid — the newest point is not pinned to the edge.**
  Pinning looks calmer, but it breaks continuity: the head is drawn at the
  border no matter what the phase is, so when the next sample arrives the old
  head has to teleport left by `(1-frac)*step`, up to a full 1.18px in one
  frame. That is the once-per-interval lurch. Sliding every point by the same
  `frac*step` makes the array shift and the phase reset cancel exactly, so the
  line glides. A short extrapolated segment keeps it touching the right border.
* **The phase is divided by the *measured* sample interval.** Samples are gated
  on the 33 ms loop, so they really arrive every ~253 ms rather than 250 ms.
  Dividing by the nominal constant made the phase reach 1.0 before the sample
  did; wrapping it there threw away up to a full step, and clamping it made the
  line stall for a frame. The interval is measured (and smoothed) per sample,
  so the phase ends where the next sample begins.

### Terminal

`st` is built at install time with four patches from the suckless queue
(`assets/st-patches/`):

| Feature | How it behaves |
|---|---|
| Scrollback | 2000 lines; `Shift+PageUp` / `Shift+PageDown` walks them |
| Mouse wheel | scrolls the buffer without a modifier; with `Shift` held the wheel bytes still go to the application, which is what `vim`, `less` and `man` expect |
| Scrollbar | a translucent, rounded thumb on the right edge; drag it or click anywhere on the strip to jump. Hidden until there is history to scroll |
| URLs | holding `Ctrl` underlines every link on screen; `Ctrl+click` opens the one under the pointer with `xdg-open`, so the desktop's default browser is used |

Links may wrap across lines: the scanner follows the wrap, so a URL that spans
two rows is underlined as a whole and opens as a whole. Trailing sentence
punctuation is trimmed, and a bare `https://` is not treated as a link.

#### The scrollbar is translucent, not a black stripe

The window is already see-through (`ST_ALPHA`), so the scrollbar has to be
composited the same way the text is, or it reads as an opaque bar pasted over
the wallpaper. Three details in `xdrawscrollbar()` do that:

* **Nothing opaque is painted.** The track is left unpainted entirely; only the
  thumb is drawn, with its own alpha, so the wallpaper keeps showing through.
* **The colours are premultiplied.** A 32-bit X pixmap is premultiplied ARGB and
  `XftDrawRect` writes straight into it without compositing, so each channel is
  scaled by the alpha first. Without that the thumb renders flat and opaque.
* **The caps are round.** Xft offers no drawing primitives past rectangles, so
  each cap is a stack of one-pixel rows inset by `r - sqrt(r^2 - dy^2)`.

Width, opacity and colour come from `config.h` (`scrollbar_width`,
`scrollbar_alpha`, `scrollbar_fg`).

#### Making st the default terminal

`Mod+Return` only covers the i3 binding. Everything else that asks for "a
terminal" - `x-terminal-emulator`, xdg-open on a `Terminal=true` desktop entry,
`sensible-terminal`, the i3-everforest helpers - goes through a different
path, so `write_default_terminal()` sets all of them:

* registers `st` with Debian's `x-terminal-emulator` alternative at priority 60
  and pins it with `--set`, so a later package install cannot take the slot back
* exports `TERMINAL=st` in `~/.xsessionrc`, which most lightweight tools check
  first
* falls back to `foot` (the rice's original terminal) if the st build failed,
  then to `kitty`

`--uninstall` removes the alternative again and returns it to `auto`.

### Implementation notes

Three constraints shaped the code, and each is commented at the site:

* **Dock, not override-redirect.** Only `_NET_WM_WINDOW_TYPE_DOCK` makes i3
  reserve the strip, but a managed dock lands in i3's dockarea, whose container
  never receives button events. The bar keeps the dock type for the strut and
  reads the pointer through `XQueryPointer` on the root window instead, so
  clicks and hovers work without an overlay window.
* **Root-relative coordinates.** `XQueryPointer(b->win, ...)` keeps reporting
  the last position inside the window once the pointer leaves, which is why an
  earlier version could not tell "pointer left" and left tooltips behind. All
  hit-testing uses root coordinates, which also survive i3 reparenting the dock.
* **Baseline snapshot.** Hovering used to trigger a full repaint (eleven
  modules plus text shaping) at 30 Hz. The bar now keeps an image of itself
  without any veil and restores just the affected pill from it, which cut the
  hover cost from 3.7 % to 1.3 % CPU.

## Bar dependencies

Every pill on the bar calls a program, and a missing program means a click that
silently does nothing. The installer therefore audits them:

| Pill | Calls | Package |
|---|---|---|
| workspaces / window | i3 itself (`i3-msg`) | `i3-wm` |
| colour picker | `i3-everforest-pick` → slop, maim, imagemagick, xclip | `slop`, `maim`, `imagemagick`, `xclip` |
| screenshot | `i3-everforest-shot` → maim/slurp, xclip | `maim`, `slop`, `xclip` |
| input method | `i3-everforest-ime` → fcitx5 / ibus, else `setxkbmap` | optional (`fcitx5`/`ibus`) |
| notifications | `i3-everforest-notifications` → dunstctl, notify-send | `dunst`, `libnotify-bin` |
| launcher | `rofi -show drun` | `rofi` |
| power | `i3-everforest-powermenu` → rofi + systemctl | `rofi` |
| disk/CPU | `i3-everforest-sysinfo`, monitor → btop | `btop` |
| clock | `i3-everforest-calendar` → cal | `bsdmainutils` |
| network | `i3-everforest-wifi` → nmcli, rofi | `network-manager`, `rofi`; right-click uses `nm-connection-editor` (`network-manager-gnome`) |

The rofi/pavucontrol/nm-connection-editor set is installed by a dedicated
**bar actions** group that runs with the dotfiles component, so the buttons
keep working even with `--no-apps`.

## Polybar layout

| Order | Module | Notes |
|---|---|---|
| 1 | **internal/i3** | lime pill for the focused workspace, plain numbers otherwise |
| 2 | **internal/xwindow** | the focused window's title, centred |
| 3 | **internal/pulseaudio** | sink volume with a mute state |
| 4 | **internal/backlight** | `60% ☀`, falls back to a dim glyph |
| 5 | **custom/separator** | the tall divider |
| 6 | **custom/ime** | input method, `fcitx5-remote -t` |
| 7 | **custom/sysinfo** | disk and CPU, `75% 🖴 6% ⚙` |
| 8 | **custom/launcher** | green pill, opens rofi |
| 9 | **custom/notifications** | violet round button |
| 10 | **custom/power** | red round button, opens the power menu |
| 11 | **clock** | `%H:%M` |
| 12 | **wlan** | wifi glyph, opens `nm-connection-editor` |

Colours are sampled pixel-by-pixel from the reference screenshot: bar
`#171b1c`, pill `#2f3336`, text `#d3c6aa`, cream `#fffbef`, lime `#b9ff66`,
launcher `#00ff00`, notifications `#7c7aff`, power `#fa3433`.

### Why helper scripts

Polybar's `internal/pulseaudio` exposes only the sink; the reference shows
speaker and microphone together in one pill, so
`/usr/local/bin/i3-everforest-volume` prints both readings and a `custom`
module renders them.

Polybar's `internal/backlight` disappears when there is no
`/sys/class/backlight`, which silently shifts every control after it.
`/usr/local/bin/i3-everforest-brightness` reads sysfs directly, falls back to
`ddcutil` for external monitors, then to a RandR gamma change, and finally
shows a dimmed glyph, so the pill never disappears.

### Colour picker

Debian ships **no** colour-picker package (`hyprpicker` is Wayland-only and
not packaged here), so the eyedropper is backed by
`/usr/local/bin/i3-everforest-pick`: click one pixel with `slop -p`, read it
with ImageMagick and copy the hex value with `xclip`. The module calls it with
`notify`, so a desktop notification also shows the picked colour.
`imagemagick` is installed with the optional apps.

### Icon font

The bar and the prompt use Nerd Font glyphs. Debian ships no Nerd Font package
and its `fonts-font-awesome` is only 4.7, so **Symbols Nerd Font is embedded in
the installer** and installed into `~/.local/share/fonts`, then registered with
`fc-cache`. Without it every bar icon renders as an empty box.

## Rofi

A flat `#1e2326` panel with a 1 px cream border and a 12 px radius, an inset
`#2f3336` search field, and a lime selection with dark text. The theme is
`~/.config/rofi/i3-everforest.rasi`; every helper references it, so all menus
(drun, wifi, power, notifications, colour) look identical.

---

## Login screen: SDDM + SilentSDDM

A minimal Debian install has no greeter at all — it boots to a TTY, so there is
no way to *choose* the i3 session. The **sddm** component fixes that end to end:

* installs SDDM **with its full Qt6 QML runtime** (a bare `apt install sddm`
  shows a black screen: `sddm` does not depend on the QML modules the theme
  imports, nor on the SVG image plugin that renders its icons);
* installs the [SilentSDDM](https://github.com/uiriansan/SilentSDDM) theme into
  `/usr/share/sddm/themes/silent` with its **stock configuration**
  (`configs/default.conf`, pinned in `metadata.desktop`);
* writes `/etc/sddm.conf.d/10-i3-everforest.conf` (a drop-in, so the
  distribution's `/etc/sddm.conf` is never edited) with `Current=silent`, the
  `InputMethod` / `GreeterEnvironment` the theme needs, and an explicit `[X11]`
  section so the greeter runs on the X server SDDM manages;
* installs the theme's bundled RedHatDisplay fonts system-wide;
* points `display-manager.service` at SDDM (taking the alias over from any
  existing greeter), enables `sddm.service` and sets `graphical.target` as the
  default, so the next boot lands on the login screen;
* adds `/usr/local/bin/i3-everforest-session`, which exports
  `XDG_CURRENT_DESKTOP=i3`, `XDG_SESSION_TYPE=x11` and the toolkit hints, then
  runs i3 inside `dbus-run-session`.

`--uninstall` puts the previous display manager back (both the
`display-manager.service` symlink and `/etc/X11/default-display-manager`) and
restores the previous default target.

### Why a bare `libpam-systemd` matters

`libpam-systemd` is only a **Recommends** of `sddm` (and of `systemd-sysv`), so
an install that passes `--no-install-recommends` silently leaves it out. Without
`pam_systemd` the login creates no logind session, `/run/user/<uid>` is never
made, and every XDG consumer falls back to a world-readable `/tmp`: the greeter
accepts the password and the session comes up half broken.

The installer therefore lists `libpam-systemd` explicitly in the core set, and
`--only-sddm` re-checks for `pam_systemd.so` and installs it if it is missing,
so re-running the script repairs a machine that was installed before the fix.

To make this kind of failure diagnosable, `/usr/local/bin/i3-everforest-session`
logs to `/tmp/i3-everforest-session.log` and records the runtime directory it
ends up using.

### Desktop dependencies for a bare install

The **core** component pulls the X11 stack a from-scratch Debian needs and does
not have: the server and its input/video drivers (`xserver-xorg`,
`xserver-xorg-input-libinput`, `xserver-xorg-video-all`), `xinit`, `xauth`,
`dbus`/`dbus-x11`, polkit and an authentication agent,
`pipewire`+`wireplumber`+`pulseaudio-utils` for sound, NetworkManager, the
JetBrains Mono / Font Awesome / emoji fonts, the GTK engines needed by the
theme, and the small utilities the keybindings call (`maim`, `slop`, `xclip`,
`brightnessctl`, `playerctl`, `jq`, `curl`, `sudo`, `xdg-utils`).

---

## Options

| Option | Meaning |
|---|---|
| `-y`, `--yes` | install with defaults, no menu |
| `--user NAME` | desktop user (default: the sudo invoker) |
| `--no-apps` | skip the extra applications |
| `--no-theme` / `--no-icons` / `--no-wallpaper` | skip a visual component |
| `--no-dots` / `--no-session` / `--no-shell` | skip configs / login entry / shell extras |
| `--no-sddm` | skip SDDM + the SilentSDDM theme |
| `--only-sddm` | install/reconfigure only the login screen |
| `--only-dots`, `--only-theme`, `--only-shell`, `--only-wallpaper`, `--only-sddm` | run one component |
| `--no-apt-update` | do not refresh the package lists |
| `--opacity LEVEL` | bar transparency: `solid` (default), `soft`, `clear` |
| `-u`, `--uninstall` | remove everything this script installed |
| `--keep-packages` | with `--uninstall`, leave the apt packages alone |
| `--extract-assets DIR` | dump the bundled theme/icons/wallpaper and exit |
| `--list` | print the component list |
| `-n`, `--dry-run` | show what would be done |
| `-h` / `-v` | help / version |

---

## What gets installed

**Packages** — `i3-wm i3status i3lock xinit xserver-xorg x11-xserver-utils
x11-utils xserver-xorg-video-all xserver-xorg-input-libinput xauth dbus-x11
xcape numlockx xinput x11-xkb-utils python3-gi gir1.2-gtk-3.0
python3-xlib python3-i3ipc kitty rofi dunst feh xwallpaper picom dbus
libpam-systemd polkitd lxpolkit brightnessctl playerctl network-manager
pipewire wireplumber pulseaudio-utils fonts-jetbrains-mono fonts-font-awesome
fonts-noto-color-emoji gtk2-engines-murrine gnome-themes-extra librsvg2-common`
plus the optional `pcmanfm gvfs btop fastfetch pavucontrol network-manager-gnome
imv mpv flameshot swappy cliphist imagemagick`.

The screenshot and colour-picker tools (`maim`, `slop`, `xclip`, `xdotool`,
`xprintidle`, `xss-lock`) are **bar actions**, not optional apps: they are
installed with the dotfiles component so the bar buttons keep working even
with `--no-apps`.

**Configuration**

```
~/.config/i3/config                window manager + keybindings
~/.config/i3-everforest/bar.json   bar layout (mirrors the Waybar config)
/usr/local/bin/i3-everforest-bar    the bar program
~/.config/rofi/{config.rasi,i3-everforest.rasi}
~/.config/kitty/kitty.toml
~/.config/dunst/dunstrc
~/.config/picom/picom.conf
~/.config/i3/i3lock-color.xresources
~/.config/btop/themes/everforest.theme
~/.config/gtk-3.0/settings.ini
~/.config/gtk-4.0/{settings.ini,gtk.css,gtk-dark.css,assets}   (libadwaita)
~/.gtkrc-2.0
~/.xsessionrc                      X11 session environment
~/.Xresources                      Xft / cursor settings
~/.local/share/i3-everforest/wallpaper.jpg
/usr/share/themes/Everforest-Dark-BL-LB
/usr/share/icons/Material-Black-Lime-Numix-FLAT
/usr/share/xsessions/i3-everforest.desktop
/usr/local/bin/i3-everforest-session   session launcher used by the entry
/usr/local/bin/st                   the terminal (built from source at install)
/usr/local/src/i3-everforest-st     st source tree + the patches that were applied
/usr/local/share/applications/st.desktop   so launchers list the terminal
/usr/local/bin/mf                  the two-column fetch block
/usr/share/sddm/themes/silent      SilentSDDM (stock configs/default.conf)
/etc/sddm.conf.d/10-i3-everforest.conf
/usr/share/fonts/silent-sddm       RedHatDisplay, used by the greeter
```

### Design notes

* **Colours** come from the Everforest dark palette as it appears in the
  screenshots: background `#1e2326`, surface `#2f3336`, foreground `#d3c6aa`,
  lime accent `#b9ff66` (taken from the folder icons, so the bar and the icons
  agree), green `#a7c080`, blue `#7fbbb3`, red `#e67e80`, yellow `#dbbc7f`.
* **Bar** — floating pills on a near-black strip: workspaces on the left,
  window title centred, system modules on the right, active workspace filled
  with lime, exactly as in the reference.
* **Borders** are a 1 px cream outline on the focused window, 8 px gaps.
* **`XDG_CURRENT_DESKTOP`** — the session launcher and `~/.xsessionrc` export
  `i3` explicitly, so portals, GTK and Qt agree on what desktop is running.

### Keybindings

| Keys | Action |
|---|---|
| `Mod+Return` | terminal (st) |
| `Mod+D` | application launcher (rofi) |
| `Mod+E` | files (pcmanfm) |
| `Mod+Shift+Return` | btop |
| `Mod+Shift+E` | power menu (rofi) |
| `Mod+1..8` | workspaces |
| `Mod+Shift+C` | reload i3 |
| `Mod+Shift+R` | restart i3 |
| `Mod+Escape` | lock screen (i3lock) |
| `Print` / `Mod+Print` | full / region screenshot |
| `Mod+Shift+Print` | flameshot region capture |
| `Mod+F`, `Mod+W`, `Mod+R`, `Mod+Shift+Space` | fullscreen, tabbed, resize mode, float |
| `Mod+H/J/K/L` | focus left/down/up/right |

`Print` copies the whole screen to the clipboard, `Mod+Print` copies a dragged
region, and `Mod+Shift+Print` opens that region in swappy — the same three
bindings as the sway version. Caps Lock acts as Ctrl, and a touchpad gets tap
to click, natural scrolling and disable-while-typing, exactly like the sway
`input` blocks (applied by `i3-everforest-input` at session start).

`Mod` is the Super/Windows key. `Caps Lock` is mapped to `Ctrl` by the
keyboard configuration.

---

## Safety

* **Idempotent** — running it twice changes nothing; unchanged files are
  reported as `unchanged`.
* **Backups** — every file that is overwritten is copied to
  `~/.local/state/i3-everforest/backups/<timestamp>/` before being touched,
  and the original path is recorded in `backup-map.tsv`.
* **Manifest** — `manifest.list` records the packages, files and directories
  created, so `--uninstall` only removes what this script added.
* **Uninstall restores first, deletes second**, so a pre-existing file is never
  left missing.
* **Validation** — at the end, `i3 -C` parses the generated config, the bar
  program is syntax-checked and its JSON layout is cross-checked (every listed
  module must be defined and have a known type), `rofi -dump-theme` validates
  the theme when a display is reachable, and `kitty` is checked against its
  configuration. A real failure is reported as `✘`; the run continues so you
  can still log in and fix it.
* `--uninstall --keep-packages` leaves your package set untouched (recommended).

Everything the script writes is listed above; nothing else is modified.

---

## Layout of this repository

```
i3-setup.sh                    the deliverable: one self-contained script
src/build-i3.sh                reassembles the installer from src/i3/ + assets/
src/i3/10-header.sh               palette, helpers, traps
src/i3/20-tui.sh                  the line-based English TUI
src/i3/30-preflight.sh            distro/user checks, manifest, backups
src/i3/40-packages.sh             apt handling
src/i3/50-theme.sh                GTK theme install
src/i3/55-icons.sh                icon theme install
src/i3/57-wallpaper.sh            wallpaper + icon font
src/i3/60-dotfiles.sh             every configuration file
src/i3/70-shell.sh                helpers: mf, bar actions, lock, power, prompt
src/i3/75-session.sh              xsessions entry + session launcher
src/i3/77-sddm.sh                 SDDM + SilentSDDM
src/i3/80-uninstall.sh            restore/remove logic
src/i3/85-payload.sh              embedded-asset reader
src/i3/90-main.sh                 argument parsing and orchestration
assets/                        the payload sources (theme, icons, wallpaper)
assets/bar-i3/src/              the C bar: config.h, bar.h, bar.c,
                               modules.c, draw.c, tooltip.c, util.c
assets/sddm/silent/            SilentSDDM theme (login background included)
```

The numeric prefixes on `src/i3/*.sh` are load-bearing: `build-i3.sh` globs
`10-*`, then `20-*`, `30-*`, `40-*`, `5*`, `6*`, `70-*`, `75-*`, `77-*`,
`80-*`, `85-*`, `90-*` and concatenates them in that order. Functions must be
defined before the file that calls them, so renaming these files without
updating the glob breaks the build.

`build-i3.sh` concatenates `src/i3/*.sh` in that order and appends the compressed
assets as base64 blocks after `__I3_EVERFOREST_PAYLOAD_BELOW__`.

The bar sources are compiled at install time (`libcairo2-dev`,
`libpango1.0-dev`, `libx11-dev`), so the payload ships source rather than a
prebuilt binary and the result matches the target's ABI.

### Rebuilding

```sh
./src/build-i3.sh                           # -> i3-setup.sh
./i3-setup.sh --list         # sanity check
bash -n i3-setup.sh          # syntax check
```

---

## Tested

Verified on Debian 13 (trixie) in an isolated chroot:

* full install, `--only-dots`, `--only-theme`, `--only-shell`, `--only-sddm`,
  `--uninstall`, `--extract-assets`, `--list`, `--version`;
* a **bare `debian:trixie` container** (no desktop, no greeter): the full
  install completed and the SilentSDDM greeter rendered;
* idempotent re-run;
* a live headless X session (Xvfb + i3) with the GTK bar, kitty, rofi, dunst
  and the wallpaper, compared against the reference screenshot — every bar
  pill, the lime workspace capsule, the rofi launcher, the power menu, the
  notification style and the lock screen were rendered and checked;
* the SDDM greeter rendering the SilentSDDM theme and listing the
  "i3 (Everforest)" session, and the session launcher starting i3 with
  `XDG_CURRENT_DESKTOP=i3` and a D-Bus session bus;
* every config-generated shortcut confirmed firing against a live i3 session
  (`Mod+Return`, `Mod+D`, `Mod+E`, `Mod+Shift+E`, `Mod+1..8`, lock, screenshot);
* `--uninstall` round-trip: 30 files restored from backup, 35 removed, empty
  directories tidied, then a clean reinstall on the same machine.

## Requirements

Debian 13 (amd64/arm64), a normal desktop user (uid ≥ 1000), root via `sudo`.
