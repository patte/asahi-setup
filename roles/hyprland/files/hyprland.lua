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

    -- Nothing follows this to put the wallpaper back: hyprpaper reads its own
    -- config at startup, and narchy owns that config through a source line, so
    -- the picture for the current theme is up before anything else asks.
    hl.exec_cmd("hyprpaper")
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
        -- background, which is the intent. The splash is its own switch: the
        -- logo and the hyprBot one-liner under it are drawn separately, so
        -- silencing one leaves the other talking.
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        disable_splash_rendering = true,
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
-- habits depend on. 0.49+ syntax: what the gesture *is* now lives here, in
-- hl.gesture, rather than in the gestures{} toggle it replaced. The
-- gestures:workspace_swipe_* tuning below did not go away with that toggle,
-- though, and is what decides when a swipe counts.
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

-- Stock, this needs far more travel than macOS to commit, and a swipe that
-- falls short animates most of the way and then snaps back to where it started.
--
-- Distance alone decides that here, and the two numbers multiply: the commit
-- threshold is swipe_distance * cancel_ratio, so neither can be read on its own.
-- Stock was 0.5 of 300, meaning 150px of finger travel — half a comfortable
-- swipe — before it would commit. 0.08 of 300 is 24px, about a sixth of that.
-- Below roughly 15px there is nowhere left to go: direction_lock only decides
-- which axis a swipe belongs to after 10px, so a commit threshold near that
-- would fire before the gesture has been classified.
--
-- swipe_distance is left at its stock 300 because it does not only set that
-- threshold — it is also the travel that maps to one whole workspace, and so
-- doubles as the gain, as its inverse. There is no other multiplier to reach
-- for: scroll_factor is for scroll axis events and never reaches a swipe, and
-- libinput hands over gesture deltas unaccelerated, so sensitivity and
-- accel_profile do not either. On this 1920 logical px wide panel:
--
--     gain = 1920 / 300 = 6.4 on-screen px per px of finger
--
-- Shortening it to 160 and then 200 was tried, and both track the finger too
-- fast to follow comfortably. Stock gain turns out to be right; only the
-- threshold was ever wrong. Since the threshold is the product of the two, that
-- is what cancel_ratio is for, and it carries the whole change on its own here.
-- Move one and the other has to move with it to hold 24px.
--
-- min_speed_to_force is the other path, committing on speed regardless of
-- distance, and it is deliberately switched off. It cannot be turned off by
-- setting it to zero — the test is whether the swipe exceeds it, so zero means
-- every swipe forces the change rather than none. A number no swipe can reach
-- is the only way to disable it, hence the sentinel.
--
-- Worth knowing why it is not simply tuned instead: at its stock 30px per event
-- it sat above what even a fast swipe produces (the same events that drive the
-- zoom above deliver roughly 10px each), so it never fired at all and every
-- swipe silently fell back to the 150px. Dropping it to 14 did make flicks
-- commit, but with the travel requirement now at 24px the distance path already
-- catches anything worth calling a flick, and a second, speed-based way to
-- commit only adds a way to switch workspaces by accident.
hl.config({
    gestures = {
        workspace_swipe_distance           = 300,
        workspace_swipe_cancel_ratio       = 0.08,
        workspace_swipe_min_speed_to_force = 100000,

        -- Stock, a swipe clamps at the neighbouring workspace however far it
        -- runs, so crossing two takes two gestures. This lets one long swipe
        -- keep going. The trackpad has the travel for it: the first workspace
        -- costs the 24px above, and each one after that a further whole
        -- swipe_distance, so +2 is about 324px and +3 about 624px. That is a
        -- lot of finger, but it is only ever spent when the swipe asks for it —
        -- a short flick still lands exactly one across, as before.
        workspace_swipe_forever            = true,

        -- Swiping past the last workspace conjures a new one. Harmless at the
        -- stock threshold, but a shorter, twitchier swipe makes overshooting
        -- the end of the list into an accident rather than an intent — and
        -- more so now that a swipe is allowed to run past its neighbour.
        workspace_swipe_create_new         = false,
    },
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
-- is spent, so 130 gives a coast of about 600ms.
--
-- Same model Apple uses: UIScrollView.decelerationRate is a per-millisecond
-- factor on velocity, i.e. exponential decay. Its two documented values convert
-- to time constants of -1/ln(rate): .normal = 0.998 is 499ms, .fast = 0.99 is
-- 99ms. Apple publishes no constant for the zoom inertia itself, so those are
-- the closest documented reference points.
--
-- 220 was tried and is too long, because the coast is velocity * this constant
-- and the swipe velocities here are high: an ordinary unhurried swipe runs at
-- ~0.006 exponent/ms, so 220 coasts a further e^1.3, nearly 4x, every single
-- time you lift off. That reads as the zoom refusing to stop.
local ZOOM_FLING_TIME   = 130   -- ms
-- Ceiling on what one fling may add, as an exponent: e^1.45 is about 4.3x. The
-- coast is the integral of a decaying velocity, which is velocity * time
-- constant, so capping the handover velocity at MAX/TIME bounds the whole
-- coast no matter how hard the swipe was flicked.
--
-- These two are coupled and must be tuned together. MAX/TIME has to stay above
-- ordinary swipe velocity or the cap stops being a ceiling and becomes the only
-- value: at 0.8/220 it sat at 0.0036, below the 0.005-0.01 an unhurried swipe
-- produces, so every release clamped to it and a flick and a steady lift-off
-- came out identical — the zoom ended slow every time, whatever you did.
-- Lengthening the coast therefore means raising MAX in step; 1.45/130 holds the
-- cap at 0.011, which only a real flick reaches.
local ZOOM_FLING_MAX    = 1.45
local ZOOM_FLING_TICK   = 8     -- ms between coast frames, ~120Hz
-- Below this exponent-per-ms a fling is really a slow release, so it just stops.
-- Decelerating before lifting drops the smoothed velocity well under this; only
-- lifting while still moving gets a coast. The old 0.00005 was ~100x below any
-- real swipe, so nothing ever took that branch.
local ZOOM_FLING_MIN    = 0.002

-- cursor:zoom_factor is an animated property, so Hyprland eases towards every
-- value set below rather than jumping to it. Left alone it inherits the global
-- animation: 800ms on the "default" bezier, which spends half its duration on
-- the last 5% of the distance. That tail is a second ease-out underneath the
-- coast above, and it interpolates linearly in the factor while the eye reads
-- zoom logarithmically — so settling to 1x crawls visibly through the last
-- 1.5x-1.0x while the same residual at 12x is invisible. Zooming out always
-- ended slow because of it.
--
-- Short on purpose. The gesture retargets this every few ms, so the animation's
-- job here is only to smooth between libinput events; the feel comes from the
-- swipe and the coast, and a long curve here just fights them. 100ms is long
-- enough to hide the event granularity and short enough not to lag the finger.
--
-- "quick" is upstream's own name and control points for this curve, and what
-- their example config puts on zoomFactor. Only "linear" and "default" are
-- built in, so it has to be defined before it can be named. Its tail is 31% of
-- the duration for the last 5% of the distance — at 100ms that is 31ms, short
-- enough not to reintroduce the crawl, while still landing softer than linear.
-- That softness is mostly for the mouse wheel below, where each notch is a
-- single step and linear reads as mechanical.
hl.curve("quick", { type = "bezier", points = { {0.15, 0}, {0.1, 1} } })

hl.animation({ leaf = "zoomFactor", enabled = true, speed = 1, bezier = "quick" })

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

hl.layer_rule({
    -- The launcher opens with a long, off-centre swell without this, and the
    -- cause is not where it looks. wofi commits its layer surface twice: GTK
    -- puts up a 50x40 placeholder before it has measured anything, then resizes
    -- to the real 976x496. Both are centred, so the geometry is never actually
    -- wrong — what is wrong is the transition between them.
    --
    -- Hyprland animates that resize on the layers curve, and a layer's buffer is
    -- drawn 1:1 from the box's top-left and clipped, never scaled to fit. So the
    -- list is painted at its final size inside a box that starts at the centre
    -- of the screen and grows outwards: the visible content begins below and to
    -- the right of where it belongs and slides up and left into place. On the
    -- stock global curve that takes most of a second, since "default" spends
    -- half its duration on the last 5% of the distance.
    --
    -- There is nothing to fix on the animation itself. The style only picks the
    -- map-in transition, and a resize is animated whichever one is set — "fade"
    -- was tried and changes none of the above. Suppressing the animation for
    -- this one namespace is the fix, and it is the right scope anyway: waybar
    -- and mako map at the size they mean to keep, so their animations are fine
    -- and stay on. The dmenu popups the bar's scripts shell out to are wofi too,
    -- and get the same treatment for the same reason.
    name  = "wofi-maps-twice",
    match = { namespace = "^wofi$" },

    no_anim = true,
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
