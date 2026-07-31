-- Hyprland config — source of truth, installed to ~/.config/hypr/hyprland.lua
-- by roles/hyprland. Edit here and re-run the role; edits to the installed copy
-- are reverted on the next run.
--
-- Hyprland 0.5x configs are Lua, not the old hyprland.conf hyprlang format.
-- The `hl.*` API used below is what upstream's example config uses at 0.56.
-- Reference: https://wiki.hypr.land/Configuring/
--
-- Deliberately minimal: no colours, no wallpaper, no bar styling, no animation
-- tuning. This is the "does it work" layer. waybar/mako/wofi run on their stock
-- configs for now.
--
-- keyd sits below the compositor (evdev), so its rewrites apply here exactly as
-- they do under GNOME: Caps Lock is Ctrl, and SUPER + C/V/X are copy/paste/cut.
-- Those three never reach Hyprland, so nothing below may bind them.

------------------
---- MONITORS ----
------------------

-- Internal panel only for now. "auto" scale picks 2 on this display; if text
-- comes out the wrong size, set scale = 2 explicitly rather than a fractional
-- value, which costs a blurry composite pass.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

---------------------
---- MY PROGRAMS ----
---------------------

local terminal    = "ghostty"
local fileManager = "nautilus"
local menu        = "wofi --show drun"

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    -- Portals and user units started later inherit their environment from the
    -- systemd/D-Bus activation environment, not from Hyprland. Without this,
    -- file pickers and screen sharing come up empty.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")

    -- GNOME provides both of these for free; a bare compositor does not.
    -- Without the polkit agent, anything asking for admin rights fails with no
    -- prompt at all. Without the keyring, saved secrets and ssh keys are gone.
    hl.exec_cmd("systemctl --user start hyprpolkitagent.service")
    hl.exec_cmd("/usr/bin/gnome-keyring-daemon --start --components=secrets,ssh")

    hl.exec_cmd("waybar")
    hl.exec_cmd("mako")
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Electron apps (VS Code) default to XWayland, which on a HiDPI panel means
-- blurry text. "auto" makes them native Wayland clients.
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Placeholder. Theming, colours and a real wallpaper come later; these are just
-- the structural bits that decide how windows are laid out.
hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 10,
        border_size = 2,
        layout      = "dwindle",

        -- Resize by dragging borders and gaps, not just with the keyboard.
        resize_on_border = true,
    },

    dwindle = {
        preserve_split = true,
    },

    misc = {
        -- No mascot wallpaper. Until the theming pass this leaves a plain
        -- background, which is the intent.
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
    },
})

---------------
---- INPUT ----
---------------

hl.config({
    input = {
        -- "German (Switzerland, Macintosh)" — the same ch+de_mac that GNOME is
        -- set to, so the two sessions type identically.
        kb_layout    = "ch",
        kb_variant   = "de_mac",

        follow_mouse = 1,
        sensitivity  = 0,

        touchpad = {
            natural_scroll      = true,
            disable_while_typing = true,
        },
    },
})

-- Three-finger horizontal swipe between workspaces, the one gesture GNOME
-- habits depend on. 0.49+ syntax; the old gestures{} block is gone.
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER"

hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + R",      hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd(fileManager))

-- Q closes, not C: keyd eats SUPER + C before Hyprland can see it.
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exit())

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Workspaces on mainMod + [0-9], move the active window with SHIFT
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scratchpad
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize with mainMod + LMB/RMB
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Screenshots. Print grabs a region to the clipboard, SHIFT + Print the whole
-- screen to a file.
hl.bind("Print",         hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy'))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd('grim "$HOME/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png"'))

-- Laptop keys. GNOME handles these itself; here they have to be bound.
-- `locked` means they keep working with the screen locked.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                 { locked = true, repeating = true })

hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

hl.window_rule({
    -- Apps asking to maximize themselves fights the tiling layout.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

hl.window_rule({
    -- Upstream's fix for XWayland drag-and-drop losing focus.
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})
