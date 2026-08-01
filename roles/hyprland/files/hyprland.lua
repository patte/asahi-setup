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
    scale    = "1.5",
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

-- Zoom the screen around the cursor, macOS style. Declared here rather than
-- down with the keybinds because the gesture callback below closes over them,
-- and a Lua closure cannot capture a local that is not in scope yet.
-- ZOOM_MAX is our own ceiling. Hyprland declares cursor:zoom_factor with a max
-- of 10, but does not enforce it — larger values are accepted and rendered.
-- 1 is a real floor, though: below it the zoom is meaningless.
local ZOOM_MAX          = 15
-- Per wheel notch, multiplicative: n notches land on ZOOM_STEP^n. Mouse only.
local ZOOM_STEP         = 1.1
-- Per unit of swipe delta, in the exponent, so a whole swipe comes out as
-- exp(rate * distance) and the zoom-per-centimetre stays constant. Trackpad only.
local ZOOM_GESTURE_RATE = 0.008
-- Inertia, for the swipe only. Lifting the fingers hands the zoom over to a
-- velocity that decays exponentially with this time constant, so the zoom keeps
-- running and eases out instead of stopping dead. ~4.5 time constants until it
-- is spent, so 220 gives a coast of about a second.
--
-- Same model Apple uses: UIScrollView.decelerationRate is a per-millisecond
-- factor on velocity, i.e. exponential decay. Its two documented values convert
-- to time constants of -1/ln(rate): .normal = 0.998 is 499ms, .fast = 0.99 is
-- 99ms. 220 sits between them, nearer fast. Apple publishes no constant for the
-- zoom inertia itself, so those are the closest documented reference points.
-- .fast was tried here and is too abrupt; 220 is the keeper.
local ZOOM_FLING_TIME   = 220   -- ms
-- Ceiling on what one fling may add, as an exponent: e^0.8 is about 2.2x. The
-- coast is the integral of a decaying velocity, which is velocity * time
-- constant, so capping the handover velocity at MAX/TIME bounds the whole
-- coast no matter how hard the swipe was flicked.
local ZOOM_FLING_MAX    = 0.8
local ZOOM_FLING_TICK   = 8     -- ms between coast frames, ~120Hz
-- Below this exponent-per-ms a fling is really a slow release, so it just stops.
local ZOOM_FLING_MIN    = 0.00005

-- Zoom by an exponent, clamped. Returns where it landed so the coast can tell
-- it has hit a limit and stop pushing against it.
local function zoomByExponent(exponent)
    local current = hl.get_config("cursor:zoom_factor") or 1
    local target  = math.max(1, math.min(ZOOM_MAX, current * math.exp(exponent)))
    hl.config({ cursor = { zoom_factor = target } })
    return target
end

-- Handover velocity for the coast, in exponent per ms, and the timer that
-- burns it off. Declared before the timer because its own callback disables it.
local zoomVelocity, zoomLastTime = 0, nil
local zoomCoast

zoomCoast = hl.timer(function()
    zoomVelocity = zoomVelocity * math.exp(-ZOOM_FLING_TICK / ZOOM_FLING_TIME)

    if math.abs(zoomVelocity) < ZOOM_FLING_MIN then
        zoomVelocity = 0
        zoomCoast:set_enabled(false)
        return
    end

    -- Stop early at either limit, rather than spinning while clamped.
    local landed = zoomByExponent(zoomVelocity * ZOOM_FLING_TICK)
    if landed <= 1 or landed >= ZOOM_MAX then
        zoomVelocity = 0
        zoomCoast:set_enabled(false)
    end
end, { timeout = ZOOM_FLING_TICK, type = "repeat" })

-- Created armed, and there is nothing to coast yet.
zoomCoast:set_enabled(false)

-- mainMod + three-finger vertical swipe. Deliberately not pinch, and not
-- mainMod + two-finger scroll, which cannot work at all: scroll reaches the
-- compositor as an axis event with source FINGER, mouse_up/mouse_down binds
-- are only dispatched for source WHEEL, and the gesture engine is fed purely
-- by libinput swipe and pinch events, which start at three fingers.
--
-- This drives the zoom by hand rather than using the built-in cursor_zoom
-- action, which ignores its own live mode unless the event is a pinch and so
-- would give a swipe just one stepped multiply at gesture start. The callback
-- gets the per-event swipe delta, so scaling the factor exponentially by it
-- keeps the zoom-per-centimetre constant however libinput chops up the swipe.
-- Fingers up is delta.y < 0, hence zooming in.
hl.gesture({
    fingers   = 3,
    direction = "vertical",
    mods      = "SUPER",
    action    = {
        -- Touching down catches an in-flight coast, the way it does on a phone.
        start = function()
            zoomCoast:set_enabled(false)
            zoomVelocity, zoomLastTime = 0, nil
        end,

        update = function(e)
            local dy       = (e.delta and e.delta.y) or 0
            local exponent = -dy * ZOOM_GESTURE_RATE
            zoomByExponent(exponent)

            -- Track velocity as a smoothed exponent-per-ms. The smoothing is
            -- what keeps one jittery last event from defining the whole fling.
            local now = e.time_ms
            if now and zoomLastTime and now > zoomLastTime then
                local instant = exponent / (now - zoomLastTime)
                zoomVelocity  = zoomVelocity * 0.7 + instant * 0.3
            end
            zoomLastTime = now
        end,

        finish = function()
            local cap = ZOOM_FLING_MAX / ZOOM_FLING_TIME
            if math.abs(zoomVelocity) < ZOOM_FLING_MIN then
                zoomVelocity = 0
                return
            end

            if math.abs(zoomVelocity) > cap then
                zoomVelocity = zoomVelocity > 0 and cap or -cap
            end

            zoomCoast:set_enabled(true)
        end,
    },
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

-- Move the focused window within the layout, same keys plus SHIFT
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down" }))

-- Workspaces on mainMod + [0-9], move the active window with SHIFT
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scratchpad
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through workspaces. On ALT because plain mainMod + scroll is the zoom
-- below, which is the more valuable use of that gesture.
hl.bind(mainMod .. " + ALT + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + ALT + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Screen zoom on scroll. Mouse only — the trackpad goes through the
-- three-finger swipe gesture above, which is what actually gets used here. The two defaults
-- that matter are already right: zoom_detached_camera holds the view still
-- while the pointer moves around inside it and pans only once it reaches the
-- edge (macOS's "zoom follows pointer at edge"), and zoom_rigid = false is what
-- allows that panning at all. The factor is an animated property, so each notch
-- eases rather than snaps. ZOOM_STEP and ZOOM_MAX are up in the gesture section.
local function zoomBy(factor)
    return function()
        local current = hl.get_config("cursor:zoom_factor") or 1
        hl.config({ cursor = { zoom_factor = math.max(1, math.min(ZOOM_MAX, current * factor)) } })
    end
end

hl.bind(mainMod .. " + mouse_up",   zoomBy(ZOOM_STEP))
hl.bind(mainMod .. " + mouse_down", zoomBy(1 / ZOOM_STEP))
hl.bind(mainMod .. " + Z", function() hl.config({ cursor = { zoom_factor = 1 } }) end)

-- Move/resize with mainMod + LMB/RMB
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Screenshots. An Apple keyboard has no Print key, so P carries these; the
-- Print pair stays bound for an external keyboard that does have one.
-- The region grab holds slurp's output in a variable and && s on it, so
-- cancelling the drag with Escape aborts instead of handing grim an empty
-- geometry and putting a broken image on the clipboard.
local shotScreen = 'grim "$HOME/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png"'
local shotRegion = 'geom=$(slurp) && grim -g "$geom" - | wl-copy'

hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd(shotScreen))
hl.bind(mainMod .. " + CTRL + P",  hl.dsp.exec_cmd(shotRegion))

hl.bind("Print",         hl.dsp.exec_cmd(shotScreen))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(shotRegion))

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
