#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════╗
# ║             hyprshelf  —  install.sh             ║
# ║  Run this once. Everything is embedded here.     ║
# ╚══════════════════════════════════════════════════╝
set -e

INSTALL_DIR="$HOME/.local/share/hyprshelf"
BIN="$HOME/.local/bin/hyprshelf"
CFG_DIR="$HOME/.config/hyprshelf"
CFG="$CFG_DIR/config.json"

# ── colours ────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
B='\033[0;34m' C='\033[0;36m' W='\033[1;37m' N='\033[0m'

banner() {
  echo -e "${C}"
  echo "  ██╗  ██╗██╗   ██╗██████╗ ██████╗ ███████╗██╗  ██╗███████╗██╗     ███████╗"
  echo "  ██║  ██║╚██╗ ██╔╝██╔══██╗██╔══██╗██╔════╝██║  ██║██╔════╝██║     ██╔════╝"
  echo "  ███████║ ╚████╔╝ ██████╔╝██████╔╝███████╗███████║█████╗  ██║     █████╗  "
  echo "  ██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══██╗╚════██║██╔══██║██╔══╝  ██║     ██╔══╝  "
  echo "  ██║  ██║   ██║   ██║     ██║  ██║███████║██║  ██║███████╗███████╗██║     "
  echo "  ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝╚═╝     "
  echo -e "${N}"
  echo -e "  ${W}A modern rounded shelf dock for Hyprland${N}"
  echo -e "  ${B}Right-click any icon to pin/unpin apps${N}"
  echo ""
}

step()  { echo -e "  ${G}→${N} $*"; }
warn()  { echo -e "  ${Y}⚠${N}  $*"; }
ok()    { echo -e "  ${G}✓${N} $*"; }
err()   { echo -e "  ${R}✗${N} $*"; }

# ── dependency detection ────────────────────────────
check_deps() {
  python3 -c "
import gi
gi.require_version('Gtk','3.0')
gi.require_version('GtkLayerShell','0.1')
from gi.repository import Gtk, GtkLayerShell
" 2>/dev/null
}

install_deps_arch()   { sudo pacman -S --needed --noconfirm python python-gobject gtk3 gtk-layer-shell python-cairo; }
install_deps_debian() { sudo apt-get install -y python3 python3-gi python3-gi-cairo gir1.2-gtk-3.0 libgtk-layer-shell-dev gir1.2-gtklayershell-0.1; }
install_deps_fedora() { sudo dnf install -y python3 python3-gobject gtk3 gtk-layer-shell python3-cairo; }

install_deps() {
  step "Installing system dependencies..."
  if command -v pacman &>/dev/null;      then install_deps_arch
  elif command -v apt-get &>/dev/null;   then install_deps_debian
  elif command -v dnf &>/dev/null;       then install_deps_fedora
  else
    warn "Could not detect package manager. Install manually:"
    echo "       python-gobject  gtk3  gtk-layer-shell"
    return 1
  fi
}

# ══════════════════════════════════════════════════════════════════
#  EMBEDDED PYTHON DOCK  (written to disk by this script)
# ══════════════════════════════════════════════════════════════════
write_dock() {
cat > "$INSTALL_DIR/hyprshelf.py" << 'PYEOF'
#!/usr/bin/env python3
"""
hyprshelf — a modern rounded shelf dock for Hyprland
Right-click any icon to pin / unpin apps.
"""
import gi, os, sys, json, subprocess
from pathlib import Path

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
gi.require_version("Gdk", "3.0")
from gi.repository import Gtk, Gdk, GLib, GdkPixbuf
from gi.repository import GtkLayerShell

CONFIG_PATH = Path.home() / ".config" / "hyprshelf" / "config.json"

DEFAULT_CONFIG = {
    "icon_size": 48,
    "padding": 12,
    "margin_sides": 16,
    "gap_bottom": 10,
    "autohide": False,
    "autohide_delay_ms": 500,
    "show_labels": False,
    "theme": "dark",
    "monitor": 0,
    "apps": [
        {"name": "Files",     "icon": "system-file-manager",  "exec": "nautilus",              "pinned": True},
        {"name": "Terminal",  "icon": "utilities-terminal",   "exec": "kitty",                 "pinned": True},
        {"name": "Browser",   "icon": "firefox",              "exec": "firefox",               "pinned": True},
        {"name": "Editor",    "icon": "text-editor",          "exec": "gedit",                 "pinned": True},
        {"name": "Settings",  "icon": "preferences-system",   "exec": "gnome-control-center",  "pinned": True},
    ],
}

# ── CSS themes ─────────────────────────────────────────────────────────────────
CSS = """
* { -gtk-icon-style: regular; }

window { background: transparent; }

.shelf-wrap {
    background: transparent;
}

/* The pill — fully rounded on all sides */
.shelf-pill {
    background-color: rgba(18, 18, 24, 0.82);
    border-radius: 22px;
    border: 1px solid rgba(255,255,255,0.10);
    box-shadow:
        0 8px 32px rgba(0,0,0,0.55),
        0 2px  8px rgba(0,0,0,0.40),
        inset 0 1px 0 rgba(255,255,255,0.08);
}

/* shelf edge — wood-grain strip sitting below the pill */
.shelf-edge {
    background: linear-gradient(
        to bottom,
        rgba(180,130,70,0.55),
        rgba(110,72,30,0.70)
    );
    border-radius: 0 0 6px 6px;
    min-height: 7px;
    margin-left: 6px;
    margin-right: 6px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.45);
}

/* icon button */
.dock-btn {
    background: transparent;
    border: none;
    border-radius: 14px;
    padding: 6px;
    transition: all 150ms cubic-bezier(.4,0,.2,1);
    outline: none;
    box-shadow: none;
}
.dock-btn:hover {
    background: rgba(255,255,255,0.11);
}
.dock-btn:active {
    background: rgba(255,255,255,0.20);
    padding: 8px 6px 4px 6px;
}
.dock-btn:focus { outline: none; box-shadow: none; }

/* running dot */
.dot-row { }
.running-dot {
    background: rgba(125,211,252,0.85);
    border-radius: 50%;
    min-width: 4px;
    min-height: 4px;
}
.active-dot {
    background: #38bdf8;
    min-width: 6px;
    min-height: 4px;
    border-radius: 3px;
}

/* separator */
.sep {
    background: rgba(255,255,255,0.10);
    min-width: 1px;
    margin-top: 10px;
    margin-bottom: 10px;
    margin-left: 4px;
    margin-right: 4px;
}

/* app name label */
.app-label {
    color: rgba(255,255,255,0.65);
    font-size: 10px;
    font-family: "SF Pro Text", "Cantarell", sans-serif;
}

/* pin badge on icon (small pin emoji overlay) */
.pin-badge {
    color: #fbbf24;
    font-size: 9px;
    font-family: monospace;
}

/* context menu */
.context-menu {
    background: rgba(24,24,32,0.96);
    border-radius: 12px;
    border: 1px solid rgba(255,255,255,0.12);
    box-shadow: 0 12px 40px rgba(0,0,0,0.6);
    padding: 4px;
}
.menu-item {
    background: transparent;
    border: none;
    border-radius: 8px;
    color: rgba(255,255,255,0.88);
    font-size: 13px;
    font-family: "SF Pro Text", "Cantarell", sans-serif;
    padding: 7px 14px;
    transition: background 100ms ease;
}
.menu-item:hover { background: rgba(255,255,255,0.10); }
.menu-item.danger { color: #f87171; }
.menu-item.danger:hover { background: rgba(248,113,113,0.12); }
.menu-sep {
    background: rgba(255,255,255,0.08);
    min-height: 1px;
    margin: 3px 8px;
}
"""

# ── helpers ────────────────────────────────────────────────────────────────────
def load_config():
    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH) as f:
                data = json.load(f)
            out = DEFAULT_CONFIG.copy()
            out.update(data)
            return out
        except Exception as e:
            print(f"[hyprshelf] config error: {e}")
    return DEFAULT_CONFIG.copy()

def save_config(cfg):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(CONFIG_PATH, "w") as f:
        json.dump(cfg, f, indent=2)

def get_running_apps():
    try:
        r = subprocess.run(["hyprctl","clients","-j"], capture_output=True, text=True, timeout=1)
        clients = json.loads(r.stdout)
        return {c.get("class","").lower() for c in clients} | \
               {c.get("initialClass","").lower() for c in clients}
    except:
        return set()

def get_active_class():
    try:
        r = subprocess.run(["hyprctl","activewindow","-j"], capture_output=True, text=True, timeout=1)
        return json.loads(r.stdout).get("class","").lower()
    except:
        return ""

def launch(exec_cmd):
    try:
        subprocess.Popen(exec_cmd.split(), stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except Exception as e:
        print(f"[hyprshelf] launch: {e}")

def get_icon(name, size):
    theme = Gtk.IconTheme.get_default()
    for n in [name, name.lower(), "application-x-executable"]:
        try:
            return theme.load_icon(n, size, Gtk.IconLookupFlags.FORCE_SIZE)
        except:
            pass
    return None

def app_keys(app):
    return [app["exec"].split()[0].lower(),
            app.get("name","").lower(),
            app.get("icon","").lower()]


# ── context menu window ────────────────────────────────────────────────────────
class ContextMenu(Gtk.Window):
    def __init__(self, app_cfg, is_pinned, on_pin, on_unpin, on_launch, on_remove_running):
        super().__init__(type=Gtk.WindowType.POPUP)
        self.set_decorated(False)
        self.set_app_paintable(True)
        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual:
            self.set_visual(visual)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.get_style_context().add_class("context-menu")

        def add_item(label, cb, danger=False):
            btn = Gtk.Button(label=label)
            btn.get_style_context().add_class("menu-item")
            if danger:
                btn.get_style_context().add_class("danger")
            btn.set_relief(Gtk.ReliefStyle.NONE)
            lbl = btn.get_child()
            if lbl: lbl.set_xalign(0.0)
            btn.connect("clicked", lambda _: (self.destroy(), cb()))
            box.pack_start(btn, False, False, 0)

        def add_sep():
            s = Gtk.Box()
            s.get_style_context().add_class("menu-sep")
            box.pack_start(s, False, False, 0)

        # App name header (non-clickable)
        header = Gtk.Label(label=app_cfg.get("name", app_cfg["exec"]))
        header.set_markup(f'<span weight="bold" foreground="#ffffff">{app_cfg.get("name","")}</span>')
        header.set_margin_top(8)
        header.set_margin_bottom(4)
        header.set_margin_start(14)
        header.set_margin_end(14)
        header.set_halign(Gtk.Align.START)
        box.pack_start(header, False, False, 0)
        add_sep()

        add_item("Open", on_launch)
        add_sep()

        if is_pinned:
            add_item("Unpin from Dock", on_unpin, danger=False)
        else:
            add_item("📌  Pin to Dock", on_pin)

        self.add(box)

        # Click outside to dismiss
        self.add_events(Gdk.EventMask.FOCUS_CHANGE_MASK)
        self.connect("focus-out-event", lambda *_: self.destroy())

    def popup_at(self, x, y):
        self.show_all()
        self.move(x, y)
        # grab pointer so click-outside dismisses
        self.get_window().set_override_redirect(True)
        Gtk.grab_add(self)
        self.grab_focus()


# ── single app button ──────────────────────────────────────────────────────────
class AppButton(Gtk.Box):
    def __init__(self, app_cfg, config, dock):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.app_cfg = app_cfg
        self.config = config
        self.dock = dock
        self._build()

    def _build(self):
        size = self.config["icon_size"]

        # Button
        self.btn = Gtk.Button()
        self.btn.set_relief(Gtk.ReliefStyle.NONE)
        self.btn.get_style_context().add_class("dock-btn")
        self.btn.set_tooltip_text(self.app_cfg.get("name", ""))

        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        # Icon
        pb = get_icon(self.app_cfg.get("icon","application-x-executable"), size)
        if pb:
            img = Gtk.Image.new_from_pixbuf(pb)
        else:
            img = Gtk.Image.new_from_icon_name("application-x-executable", Gtk.IconSize.DND)
        img.set_pixel_size(size)
        inner.pack_start(img, False, False, 0)

        self.btn.add(inner)
        self.btn.connect("clicked", self._on_click)
        self.btn.connect("button-press-event", self._on_button_press)
        self.pack_start(self.btn, False, False, 0)

        # Running dot
        dot_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        dot_row.set_halign(Gtk.Align.CENTER)
        dot_row.get_style_context().add_class("dot-row")
        self.dot = Gtk.Box()
        self.dot.set_size_request(4, 4)
        self.dot.get_style_context().add_class("running-dot")
        self.dot.set_no_show_all(True)
        dot_row.pack_start(self.dot, False, False, 0)
        self.pack_start(dot_row, False, False, 2)

        # Optional label
        if self.config.get("show_labels"):
            lbl = Gtk.Label(label=self.app_cfg.get("name",""))
            lbl.get_style_context().add_class("app-label")
            self.pack_start(lbl, False, False, 0)

    def _on_click(self, _):
        launch(self.app_cfg["exec"])

    def _on_button_press(self, widget, event):
        if event.button == 3:  # right click
            self._show_context_menu(event)
            return True

    def _show_context_menu(self, event):
        is_pinned = self.app_cfg.get("pinned", False)

        def on_launch():    launch(self.app_cfg["exec"])
        def on_pin():       self.dock.pin_app(self.app_cfg)
        def on_unpin():     self.dock.unpin_app(self.app_cfg)
        def on_remove():    self.dock.remove_running(self.app_cfg)

        menu = ContextMenu(self.app_cfg, is_pinned, on_pin, on_unpin, on_launch, on_remove)
        # Position above the cursor
        menu.show_all()
        menu.realize()
        mw, mh = menu.get_preferred_size()[1].width, menu.get_preferred_size()[1].height
        rx, ry = int(event.x_root), int(event.y_root)
        menu.popup_at(rx - mw // 2, ry - mh - 8)

    def set_running(self, running, active=False):
        if running:
            self.dot.show()
            ctx = self.dot.get_style_context()
            if active:
                ctx.add_class("active-dot")
            else:
                ctx.remove_class("active-dot")
        else:
            self.dot.hide()


# ── the dock window ────────────────────────────────────────────────────────────
class HyprShelf(Gtk.Window):
    def __init__(self):
        super().__init__()
        self.config = load_config()
        self._buttons = []
        self._hide_tid = None

        self._setup_window()
        self._setup_layer_shell()
        self._apply_css()
        self._build_ui()
        self._start_refresh()
        self.show_all()
        self._refresh_running()

    # ── window setup ────────────────────────────────────────────────────────────
    def _setup_window(self):
        self.set_title("hyprshelf")
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_app_paintable(True)
        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual:
            self.set_visual(visual)

    def _setup_layer_shell(self):
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
        GtkLayerShell.auto_exclusive_zone_enable(self)
        # Anchor to bottom centre
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT,   False)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT,  False)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.BOTTOM, 0)

        n = Gdk.Display.get_default().get_n_monitors()
        idx = min(self.config.get("monitor", 0), n - 1)
        mon = Gdk.Display.get_default().get_monitor(idx)
        GtkLayerShell.set_monitor(self, mon)

    def _apply_css(self):
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    # ── UI construction ──────────────────────────────────────────────────────────
    def _build_ui(self):
        # Outer transparent wrapper
        self._root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self._root.get_style_context().add_class("shelf-wrap")

        # Centre wrapper
        centre = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        centre.set_halign(Gtk.Align.CENTER)

        # Column: pill + edge strip
        col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        # The pill
        self._pill = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        self._pill.get_style_context().add_class("shelf-pill")

        # App row inside the pill
        self._app_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        s = self.config.get("margin_sides", 16)
        p = self.config.get("padding", 12)
        self._app_row.set_margin_start(s)
        self._app_row.set_margin_end(s)
        self._app_row.set_margin_top(p)
        self._app_row.set_margin_bottom(p)

        self._populate_app_row()

        self._pill.pack_start(self._app_row, False, False, 0)

        # Shelf edge strip
        edge = Gtk.Box()
        edge.get_style_context().add_class("shelf-edge")
        edge.set_size_request(-1, 7)

        col.pack_start(self._pill, False, False, 0)
        col.pack_start(edge, False, False, 0)

        centre.pack_start(col, False, False, 0)
        self._root.pack_start(centre, False, False, 0)
        self.add(self._root)

        # Gap below dock from screen edge
        gap = self.config.get("gap_bottom", 10)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.BOTTOM, gap)

        # Autohide
        if self.config.get("autohide"):
            self.connect("enter-notify-event", self._on_enter)
            self.connect("leave-notify-event", self._on_leave)

    def _populate_app_row(self):
        # Clear existing buttons
        for child in self._app_row.get_children():
            self._app_row.remove(child)
        self._buttons.clear()

        apps = self.config.get("apps", [])
        pinned = [a for a in apps if a.get("pinned", True)]
        unpinned = [a for a in apps if not a.get("pinned", True)]

        def add_app(app_cfg):
            btn = AppButton(app_cfg, self.config, self)
            self._app_row.pack_start(btn, False, False, 2)
            self._buttons.append((app_cfg, btn))

        def add_sep():
            s = Gtk.Box()
            s.get_style_context().add_class("sep")
            s.set_size_request(1, -1)
            self._app_row.pack_start(s, False, False, 4)

        for a in pinned:
            add_app(a)

        if pinned and unpinned:
            add_sep()

        for a in unpinned:
            add_app(a)

        self._app_row.show_all()
        # re-hide dots
        for _, btn in self._buttons:
            btn.dot.hide()

    def _rebuild(self):
        self._populate_app_row()
        self._refresh_running()

    # ── pin / unpin ──────────────────────────────────────────────────────────────
    def pin_app(self, app_cfg):
        for a in self.config["apps"]:
            if a["exec"] == app_cfg["exec"]:
                a["pinned"] = True
                app_cfg["pinned"] = True
        save_config(self.config)
        self._rebuild()

    def unpin_app(self, app_cfg):
        # If app is currently running we keep it in the dock but unpinned.
        # If not running, remove it entirely.
        running = get_running_apps()
        keys = app_keys(app_cfg)
        is_running = any(k in running for k in keys)

        for a in self.config["apps"]:
            if a["exec"] == app_cfg["exec"]:
                a["pinned"] = False
                app_cfg["pinned"] = False

        if not is_running:
            self.config["apps"] = [a for a in self.config["apps"]
                                    if a["exec"] != app_cfg["exec"]]
        save_config(self.config)
        self._rebuild()

    def remove_running(self, app_cfg):
        pass  # future: kill the process

    # ── running indicator refresh ────────────────────────────────────────────────
    def _start_refresh(self):
        GLib.timeout_add(1500, self._refresh_running)

    def _refresh_running(self):
        running = get_running_apps()
        active  = get_active_class()
        for app_cfg, btn in self._buttons:
            keys = app_keys(app_cfg)
            is_running = any(k in running for k in keys)
            is_active  = any(k == active  for k in keys)
            btn.set_running(is_running, is_active)

            # Auto-add running apps that aren't pinned & not in list
        self._maybe_add_running(running)
        return True

    def _maybe_add_running(self, running):
        known_execs = {a["exec"].split()[0].lower() for a in self.config["apps"]}
        # Hyprctl gives us class names — we'd need .desktop parsing to get exec
        # For now this hook is a no-op stub; can be extended later.
        pass

    # ── autohide ─────────────────────────────────────────────────────────────────
    def _on_enter(self, *_):
        if self._hide_tid:
            GLib.source_remove(self._hide_tid)
            self._hide_tid = None
        gap = self.config.get("gap_bottom", 10)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.BOTTOM, gap)

    def _on_leave(self, *_):
        delay = self.config.get("autohide_delay_ms", 500)
        self._hide_tid = GLib.timeout_add(delay, self._do_hide)

    def _do_hide(self):
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.BOTTOM, -80)
        self._hide_tid = None
        return False


# ── entry point ────────────────────────────────────────────────────────────────
def main():
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    if not CONFIG_PATH.exists():
        save_config(DEFAULT_CONFIG)
        print(f"[hyprshelf] wrote default config → {CONFIG_PATH}")

    dock = HyprShelf()
    dock.connect("destroy", Gtk.main_quit)
    Gtk.main()

if __name__ == "__main__":
    main()
PYEOF
}

# ══════════════════════════════════════════════════════════════════
#  MAIN INSTALL FLOW
# ══════════════════════════════════════════════════════════════════
banner

# 1 — dependency check
step "Checking dependencies..."
if check_deps; then
    ok "All Python/GTK dependencies satisfied"
else
    warn "Missing: python-gobject, gtk3, or gtk-layer-shell"
    read -rp "  Install them now? [Y/n] " yn
    case "$yn" in
        [Nn]*) warn "Skipping. The dock may not launch." ;;
        *)     install_deps && ok "Dependencies installed" ;;
    esac
fi

# 2 — create dirs
step "Creating directories..."
mkdir -p "$INSTALL_DIR" "$HOME/.local/bin" "$CFG_DIR"
ok "Directories ready"

# 3 — write Python dock
step "Writing dock to $INSTALL_DIR/hyprshelf.py ..."
write_dock
chmod +x "$INSTALL_DIR/hyprshelf.py"
ok "Dock written"

# 4 — write launcher
step "Creating launcher at $BIN ..."
cat > "$BIN" << 'EOF'
#!/usr/bin/env bash
exec python3 "$HOME/.local/share/hyprshelf/hyprshelf.py" "$@"
EOF
chmod +x "$BIN"
ok "Launcher created"

# 5 — PATH check
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    warn "~/.local/bin is not in your PATH"
    echo "       Add this to your shell rc:"
    echo -e "       ${C}export PATH=\"\$HOME/.local/bin:\$PATH\"${N}"
fi

# 6 — default config
if [ ! -f "$CFG" ]; then
    step "Writing default config to $CFG ..."
    cat > "$CFG" << 'EOF'
{
  "icon_size": 48,
  "padding": 12,
  "margin_sides": 16,
  "gap_bottom": 10,
  "autohide": false,
  "autohide_delay_ms": 500,
  "show_labels": false,
  "theme": "dark",
  "monitor": 0,
  "apps": [
    { "name": "Files",     "icon": "system-file-manager",  "exec": "nautilus",             "pinned": true },
    { "name": "Terminal",  "icon": "utilities-terminal",   "exec": "kitty",                "pinned": true },
    { "name": "Browser",   "icon": "firefox",              "exec": "firefox",              "pinned": true },
    { "name": "Editor",    "icon": "text-editor",          "exec": "gedit",                "pinned": true },
    { "name": "Settings",  "icon": "preferences-system",   "exec": "gnome-control-center", "pinned": true }
  ]
}
EOF
    ok "Default config written"
else
    ok "Config already exists at $CFG (not overwritten)"
fi

# 7 — Hyprland autostart
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
if [ -f "$HYPR_CONF" ]; then
    if grep -q "hyprshelf" "$HYPR_CONF" 2>/dev/null; then
        ok "hyprland.conf already has exec-once entry"
    else
        read -rp "  Add hyprshelf to hyprland.conf autostart? [Y/n] " yn
        case "$yn" in
            [Nn]*) warn "Skipped autostart entry" ;;
            *)
                printf '\n# hyprshelf dock\nexec-once = hyprshelf\n' >> "$HYPR_CONF"
                ok "Added exec-once = hyprshelf to hyprland.conf"
                ;;
        esac
    fi
else
    warn "hyprland.conf not found at $HYPR_CONF — add manually:"
    echo "       exec-once = hyprshelf"
fi

# 8 — done
echo ""
echo -e "  ${G}╔════════════════════════════════════════╗${N}"
echo -e "  ${G}║${N}  ${W}hyprshelf installed successfully!${N}     ${G}║${N}"
echo -e "  ${G}╠════════════════════════════════════════╣${N}"
echo -e "  ${G}║${N}  Run now:   ${C}hyprshelf${N}                   ${G}║${N}"
echo -e "  ${G}║${N}  Config:    ${C}~/.config/hyprshelf/${N}         ${G}║${N}"
echo -e "  ${G}║${N}  Tip:       ${Y}right-click to pin apps${N}     ${G}║${N}"
echo -e "  ${G}╚════════════════════════════════════════╝${N}"
echo ""
