# lucky
`lucky` is an input daemon for Xorg configured with a lua script.

## build
Note: requires Zig master, you can download builds at https://ziglang.org/download

Dependencies:
- `xcb`
- `xcb-keysyms`

To install, run `zig build -p <prefix>` where `<prefix>` is the directory that contains the `bin` folder you want it to install to.

So to install it to the system you could do:
```sh
sudo zig build -p /usr/local
```
and to install it for just the current user you could do:
```sh
zig build -p ~/.local
```

You may also define a different [build mode](https://ziglang.org/documentation/master/#Build-Mode) using `-Doptimize=<mode>`, the default is `ReleaseFast`

## features
- Bind `press` and `release` functions to keys and mouse buttons
- Bind `motion` and window `enter` and `exit` functions to mouse buttons
    - `motion_resolution` option to determine how often to read motion events. Defaults to 5 so motion binds don't overwhelm your system (i.e. every 5th motion event will call the binding's `motion` callback).
- Optional filter function to make a binding only active in specific contexts, if the filter returns false the key will be passed through to other applications
- Various API functions to make complex, contextual bindings possible

## cli flags
- `-c`, `--config` - file path to load for the config, defaults to `XDG_CONFIG_HOME/lucky/config.lua`

## api
- `lucky.bind(bind_string, { ... })` - bind a modifier+key/mouse button combination
- `lucky.cmd(command, arg1, arg2, ...)` - run a command directly, with function argument being a new argument to the command
- `lucky.shell(command_string)` - runs `command_string` under the system's shell, useful if you want to use subshells, pipelines, file redirects, etc. which are not available when running a command through `cmd`
- `lucky.is_root(window_id)` - returns true if `window_id` is the root window
- `lucky.get_root()` - returns the ID of the root window (based on the currently focused window)
- `lucky.get_parent_window(window_id)` - return the ID of the immediate non-root parent of `window_id`, if no parent exist return `window_id`
- `lucky.get_top_level_window(window_id)` - return the ID of the top level non-root parent of `window_id`, if no parents exist return `window_id`
- `lucky.get_focused_window()` - return the ID of the currently focused window
- `lucky.get_geometry(window_id)` - returns a table containing the `x`, `y`, `width`, `height`, and `border_width` of `window_id`
- `lucky.get_title(window_id)` - returns the title of `window_id`
- `lucky.get_class(window_id)` - returns the class of `window_id`
- `lucky.get_instance(window_id)` - returns the instance of `window_id`
- `lucky.reload()` - reload your config

## examples
### launch a terminal
```lua
lucky.bind('super Return', {
    press = function(window_id)
        lucky.cmd(os.getenv('TERMINAL') or 'xterm')
    end
})
```

### bind super 1-9 to switch tag in dwm
```lua
for i=1,9 do
    lucky.bind('super ' .. tostring(i), {
        press = function()
            lucky.cmd('dwmc', 'viewex', tostring(i - 1))
        end,
    })
end
```

### reload config
```lua
lucky.bind('super minus', {
    press = function(window_id)
        lucky.reload()
    end
})
```

### open clipboard in mpv
```lua 
lucky.bind('super p', {
    press = function(window_id)
        lucky.shell('mpv --force-window=immediate "$(xclip -o -sel clip)"')
    end
})
```

### horizontal mouse position as a tag switcher when holding `super alt mouse_left`
```lua
function pointer_to_tag(x, y, window_id)
    local max_x = lucky.get_geometry(lucky.get_root()).width - 1
    local percent = x / max_x
    local tag = math.floor(percent * 9) -- 9 tags
    lucky.cmd('dwmc', 'viewex', tostring(tag))
end

lucky.bind("super alt mouse_left", {
    press = pointer_to_tag,
    motion = pointer_to_tag
})
```

### vertical mouse as a volume slider if you press the left mouse button on the left edge of the screen
```lua
function volume_slider(x, y, wid)
    local max_y = lucky.get_geometry(lucky.get_root()).height - 1
    local percent = math.floor(((max_y - y) / max_y) * 100)
    lucky.cmd('pactl', 'set-sink-volume', '@DEFAULT_SINK@', tostring(percent) .. '%')
end

lucky.bind("mouse_left", {
    filter = function(x, y, wid)
        return x == 0
    end,

    press = volume_slider,
    motion = volume_slider
})
```

## future plans
- [ ] MAN PAGE!!!!!
- [ ] Pass arbitrary data on startup, so you can load thinsg dynamically in the config
    - For example, you could pass in the window manager for loading wm-specific keybinds, if you use multiple window managers
- [ ] Ability to send arbitrary inputs through the lua API, so keys can be rebound in certain contexts
- [ ] Make key repeat detectable
- [ ] Plan9-esque Mouse chording
    - I already know internally how to implement this, just need to work out the specifics of how it'll work for the user-side of things
- [ ] Expose more information to the binding callbacks, possibly shove it all in a table instead of individual function arguments
    - Mouse position for key presses
    - Mouse positions relative to the window, not just global position
    - Mouse movement relative to the last motion event for motion callback
- [ ] Look into what's possible with the X input extension
    - In particular, I'd like to implement things like touchpad and touchscreen gestures. Maybe stuff with drawing tablet input as well (pressure, for example).
    - I have a general idea of how to do stuff with this but I don't have devices to test with which makes it rather difficult to build support for these things
- [ ] Chording system
    - Could perhaps work by giving a table to a function instead, which has keys to functions or more tables for nested chords
    - Callback users can implement when updating the chord state, they could use this information to build their own whichkey-like system
- [ ] Allow users to replay a matched keybinding to other clients
    - Consider gutting the filter callback if this is implemented, since it lets you effectively do the same thing (the filter function might be a more comfortable for the common use case though, so maybe it'd still be worth keeping)
- [ ] Allow users to implement named labels for bindings. This would allow for things like enabling/disabling bindings via their label, or removing the binding entirely.
