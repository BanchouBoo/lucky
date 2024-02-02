const std = @import("std");
const log = std.log;
const mem = std.mem;
const meta = std.meta;
// const os = std.os;
const os = struct {
    pub usingnamespace std.os;
    pub const setsid = @cImport({
        @cInclude("unistd.h");
    }).setsid; // TODO: pr this function into zig std lib
};

const accord = @import("accord");
const xzb = @import("xzb");
const ziglua = @import("ziglua");

const Lua = ziglua.Lua;

// TODO: EXTENDED INPUT STUFF
//       https://github.com/Xpra-org/xpra/issues/173
//       https://www.phoronix.com/news/X-Input-2.4-Touchpad-Gestures
//       https://gitlab.freedesktop.org/xorg/xserver/-/merge_requests/530

const Binding = struct {
    lua: Lua,
    bind: BindUnion,
    mod_mask: xzb.ModMask,
    on_press: ?i32,
    on_release: ?i32,
    filter: ?i32,

    const BindUnion = union {
        key: KeyValue,
        button: ButtonValue,
    };

    pub const KeyValue = struct {
        value: xzb.Keysym,
    };

    pub const ButtonValue = struct {
        value: xzb.MouseButton,
        motion_resolution: usize,
        on_motion: ?i32,
        on_enter: ?i32,
        on_exit: ?i32,

        pub fn motion(self: ButtonValue, lua: *Lua, x: i16, y: i16, window: xzb.Window) !void {
            if (self.on_motion) |pressFn| {
                _ = lua.rawGetIndex(ziglua.registry_index, function_register);
                _ = lua.rawGetIndex(-1, pressFn);
                defer lua.pop(1);
                push(lua, x);
                push(lua, y);
                push(lua, window);
                lua.protectedCall(3, 0, 0) catch |err| {
                    log.err("{s}", .{to(lua, []const u8, -1)});
                    return err;
                };
            }
        }

        pub fn enter(self: ButtonValue, lua: *Lua, window: xzb.Window) !void {
            if (self.on_enter) |pressFn| {
                _ = lua.rawGetIndex(ziglua.registry_index, function_register);
                _ = lua.rawGetIndex(-1, pressFn);
                defer lua.pop(1);
                push(lua, window);
                lua.protectedCall(1, 0, 0) catch |err| {
                    log.err("{s}", .{to(lua, []const u8, -1)});
                    return err;
                };
            }
        }

        pub fn exit(self: ButtonValue, lua: *Lua, window: xzb.Window) !void {
            if (self.on_exit) |pressFn| {
                _ = lua.rawGetIndex(ziglua.registry_index, function_register);
                _ = lua.rawGetIndex(-1, pressFn);
                defer lua.pop(1);
                push(lua, window);
                lua.protectedCall(1, 0, 0) catch |err| {
                    log.err("{s}", .{to(lua, []const u8, -1)});
                    return err;
                };
            }
        }
    };

    pub fn press(self: Binding, args: anytype) !void {
        if (self.on_press) |pressFn| {
            var lua = self.lua;
            _ = lua.rawGetIndex(ziglua.registry_index, function_register);
            _ = lua.rawGetIndex(-1, pressFn);
            defer lua.pop(1);
            inline for (args) |arg| {
                push(&lua, arg);
            }
            lua.protectedCall(args.len, 0, 0) catch |err| {
                log.err("{s}", .{to(&lua, []const u8, -1)});
                return err;
            };
        }
    }

    pub fn release(self: Binding, args: anytype) !void {
        if (self.on_release) |releaseFn| {
            var lua = self.lua;
            _ = lua.rawGetIndex(ziglua.registry_index, function_register);
            _ = lua.rawGetIndex(-1, releaseFn);
            defer lua.pop(1);
            inline for (args) |arg| {
                push(&lua, arg);
            }
            lua.protectedCall(args.len, 0, 0) catch |err| {
                log.err("{s}", .{to(&lua, []const u8, -1)});
                return err;
            };
        }
    }

    pub fn testFilter(self: Binding, args: anytype) !bool {
        if (self.filter) |filterFn| {
            var lua = self.lua;
            _ = lua.rawGetIndex(ziglua.registry_index, function_register);
            _ = lua.rawGetIndex(-1, filterFn);
            defer lua.pop(2);
            inline for (args) |arg| {
                push(&lua, arg);
            }
            lua.protectedCall(args.len, 1, 0) catch |err| {
                log.err("{s}", .{to(&lua, []const u8, -1)});
                return err;
            };
            return to(&lua, bool, -1);
        } else return true;
    }
};

fn compileError(comptime fmt: []const u8, args: anytype) noreturn {
    @compileError(std.fmt.comptimePrint(fmt, args));
}

// TODO: get_screen_dimensions? is this different from root window?
const api = struct {
    // pub const key = struct {
    //     pub usingnamespace xzb.KeysymNames;
    // };
    //
    // pub const button = struct {
    //     pub const left = xzb.MouseButton.left;
    //     pub const middle = xzb.MouseButton.middle;
    //     pub const right = xzb.MouseButton.right;
    //     pub const scroll_up = xzb.MouseButton.scroll_up;
    //     pub const scroll_down = xzb.MouseButton.scroll_down;
    //     pub const scroll_left = xzb.MouseButton.scroll_left;
    //     pub const scroll_right = xzb.MouseButton.scroll_right;
    // };

    pub fn bind(lua: *Lua) i32 {
        if (!lua.isString(1)) {
            log.err("Expected string as first argument to lucky.{s}()", .{@src().fn_name});
            return 0;
        }
        const bind_string = to(lua, []const u8, 1);

        if (!lua.isTable(2)) {
            log.err("Binding '{s}' expected table as second argument", .{bind_string});
            return 0;
        }

        var binding: Binding = undefined;
        binding.lua = lua.*;
        var keysym: xzb.Keysym = .no_symbol;
        var mouse_button: xzb.MouseButton = .any;
        var is_mouse = false;
        binding.mod_mask = .none;
        var tokens = mem.tokenize(u8, bind_string, " ");

        while (tokens.next()) |token| {
            const mask_value = meta.stringToEnum(xzb.ModMask, token) orelse {
                if (keysym != .no_symbol or mouse_button != .any) {
                    log.err(
                        "Binding '{s}' contains two keys/buttons or a mistyped modifier\n",
                        .{bind_string},
                    );
                    return 0;
                }

                const button_prefix = "mouse_";
                if (mem.startsWith(u8, token, button_prefix)) exit: {
                    is_mouse = true;
                    const input_token = token[button_prefix.len..];
                    const button_index = std.fmt.parseInt(u8, input_token, 10) catch |err| switch (err) {
                        error.Overflow => {
                            log.err(
                                "Mouse button '{s}' from binding '{s}' out of range!\n",
                                .{ input_token, bind_string },
                            );
                            return 0;
                        },
                        error.InvalidCharacter => {
                            const mb = meta.stringToEnum(xzb.MouseButton, input_token);
                            if (mb == null or mb.? == .any) {
                                log.err(
                                    "Invalid mouse button '{s}' from binding '{s}'!\n",
                                    .{ input_token, bind_string },
                                );
                                return 0;
                            }
                            mouse_button = mb.?;
                            break :exit;
                        },
                    };
                    mouse_button = @enumFromInt(button_index);
                } else {
                    keysym = xzb.Keysym.fromName(token) catch {
                        log.err("Invalid keysym '{s}'", .{token});
                        return 0;
                    };
                }
                continue;
            };

            if (binding.mod_mask.hasAll(.{mask_value})) {
                log.err(
                    "Duplicate modifier '{s}' in binding '{s}'\n",
                    .{ @tagName(mask_value), bind_string },
                );
                return 0;
            }
            binding.mod_mask = xzb.ModMask.new(.{ binding.mod_mask, mask_value });
        }

        _ = lua.rawGetIndex(ziglua.registry_index, function_register);
        defer lua.pop(1);

        const press_type = lua.getField(2, "press");
        if (press_type == .function) {
            binding.on_press = lua.ref(-2) catch {
                log.err("Error storing press function for binding '{s}'", .{bind_string});
                return 0;
            };
        } else {
            lua.pop(1);
            switch (press_type) {
                .none, .nil => binding.on_press = null,
                else => {
                    log.err("'press' must be a function, found {s}", .{@tagName(press_type)});
                    return 0;
                },
            }
        }

        const release_type = lua.getField(2, "release");
        if (release_type == .function) {
            binding.on_release = lua.ref(-2) catch {
                log.err("Error storing release function for binding '{s}'", .{bind_string});
                return 0;
            };
        } else {
            lua.pop(1);
            switch (release_type) {
                .none, .nil => binding.on_release = null,
                else => {
                    log.err("'release' must be a function, found {s}", .{@tagName(release_type)});
                    return 0;
                },
            }
        }

        const filter_type = lua.getField(2, "filter");
        if (filter_type == .function) {
            binding.filter = lua.ref(-2) catch {
                log.err("Error storing filter function for binding '{s}'", .{bind_string});
                return 0;
            };
        } else {
            lua.pop(1);
            switch (filter_type) {
                .none, .nil => binding.filter = null,
                else => {
                    log.err("'filter' must be a function, found {s}", .{@tagName(filter_type)});
                    return 0;
                },
            }
        }

        if (is_mouse) {
            var motion: ?i32 = undefined;
            const motion_type = lua.getField(2, "motion");
            if (motion_type == .function) {
                motion = lua.ref(-2) catch {
                    log.err("Error storing motion function for binding '{s}'", .{bind_string});
                    return 0;
                };
            } else {
                lua.pop(1);
                switch (motion_type) {
                    .none, .nil => motion = null,
                    else => {
                        log.err("'motion' must be a function, found {s}", .{@tagName(motion_type)});
                        return 0;
                    },
                }
            }

            var motion_resolution: usize = 5;
            if (motion != null) {
                const motion_resolution_type = lua.getField(2, "motion_resolution");
                if (motion_resolution_type == .number) {
                    motion_resolution = to(lua, usize, -1);
                } else {
                    lua.pop(1);
                    switch (motion_resolution_type) {
                        .none, .nil => {},
                        else => {
                            log.err("'motion_resolution' must be a number, found {s}", .{@tagName(motion_type)});
                            return 0;
                        },
                    }
                }
            }

            var enter: ?i32 = undefined;
            const enter_type = lua.getField(2, "enter");
            if (enter_type == .function) {
                enter = lua.ref(-2) catch {
                    log.err("Error storing enter function for binding '{s}'", .{bind_string});
                    return 0;
                };
            } else {
                lua.pop(1);
                switch (enter_type) {
                    .none, .nil => enter = null,
                    else => {
                        log.err("'enter' must be a function, found {s}", .{@tagName(enter_type)});
                        return 0;
                    },
                }
            }

            var exit: ?i32 = undefined;
            const exit_type = lua.getField(2, "exit");
            if (exit_type == .function) {
                exit = lua.ref(-2) catch {
                    log.err("Error storing exit function for binding '{s}'", .{bind_string});
                    return 0;
                };
            } else {
                lua.pop(1);
                switch (exit_type) {
                    .none, .nil => exit = null,
                    else => {
                        log.err("'exit' must be a function, found {s}", .{@tagName(exit_type)});
                        return 0;
                    },
                }
            }

            binding.bind = .{ .button = .{
                .value = mouse_button,
                .motion_resolution = motion_resolution,
                .on_motion = motion,
                .on_enter = enter,
                .on_exit = exit,
            } };
            button_bindings.append(binding) catch {
                log.err("Ran out of memory trying to allocate space for binding!", .{});
                return 0;
            };

            var mask = xzb.EventMask.new(.{ .button_press, .button_release });
            if (motion != null or enter != null or exit != null)
                mask = xzb.EventMask.new(.{ mask, .pointer_motion });
            // if (enter != null)
            //     mask = xzb.EventMask.new(.{ mask, .enter_window });
            // if (exit != null)
            //     mask = xzb.EventMask.new(.{ mask, .leave_window });
            connection.grabButton(
                mouse_button,
                binding.mod_mask,
                true,
                screen.root,
                mask,
                .none,
                .none,
                .sync,
                .@"async",
            ) catch |err| {
                log.err("Error grabbing button for binding {s}: {!}", .{ bind_string, err });
                return 0;
            };
        } else {
            if (binding.on_press == null and binding.on_release == null) {
                log.err(
                    "Binding '{s}' is missing both press and release functions, must have at least one!",
                    .{bind_string},
                );
                return 0;
            }
            binding.bind = .{ .key = .{ .value = keysym } };
            key_bindings.append(binding) catch {
                log.err("Ran out of memory trying to allocate space for binding!", .{});
                return 0;
            };
            const keycode = (symbols.getKeycode(connection, keysym) catch |err| {
                log.err("Error trying to get keycode: {!}", .{err});
                return 0;
            })[0];
            connection.grabKey(keycode, binding.mod_mask, true, screen.root, .@"async", .sync) catch |err| {
                log.err("Error grabbing key for binding {s}: {!}", .{ bind_string, err });
                return 0;
            };
        }

        return 0;
    }

    fn execute(arena: std.mem.Allocator, argv: []const []const u8, sync: bool) void {
        const pid = os.fork() catch |err| {
            log.err("Error forking process: {!}", .{err});
            return;
        };
        if (pid == 0) {
            os.close(connection.getFileDescriptor());

            const pid2 = if (sync) 0 else os.fork() catch |err| {
                log.err("Error forking process: {!}", .{err});
                return;
            };
            if (pid2 == 0) {
                _ = os.setsid();

                const argv_buf = arena.allocSentinel(?[*:0]u8, argv.len, null) catch {
                    log.err("Ran out of memory!", .{});
                    return;
                };
                for (argv, argv_buf) |arg, *buf| buf.* = (arena.dupeZ(u8, arg) catch {
                    log.err("Ran out of memory!", .{});
                    return;
                }).ptr;

                const err = os.execvpeZ(
                    argv_buf.ptr[0].?,
                    argv_buf.ptr,
                    @ptrCast(os.environ.ptr),
                );

                log.err("Error executing command '{s}': {!}", .{ argv[0], err });
                return;
            }
            if (!sync)
                os.exit(0);
        }
        _ = os.waitpid(pid, 0);
    }

    pub fn cmd(lua: *Lua) i32 {
        const count: usize = @intCast(lua.getTop());
        if (count == 0) {
            log.err("lucky.{s}() requires at least one argument!", .{@src().fn_name});
            return 0;
        }

        var arena_allocator = std.heap.ArenaAllocator.init(allocator);
        defer arena_allocator.deinit();
        const arena = arena_allocator.allocator();

        var args = arena.alloc([]const u8, count) catch {
            log.err("Error allocating memory for lucky.{s}()!", .{@src().fn_name});
            return 0;
        };

        for (0..count) |i| {
            args[i] = to(lua, []const u8, @intCast(i + 1));
        }

        execute(arena, args, false);

        return 0;
    }

    pub fn shell(lua: *Lua) i32 {
        if (!lua.isString(1)) {
            log.err("Expected a string for lucky.{s}()!", .{@src().fn_name});
            return 0;
        }

        var arena_allocator = std.heap.ArenaAllocator.init(allocator);
        defer arena_allocator.deinit();
        const arena = arena_allocator.allocator();

        execute(arena, &.{ "sh", "-c", to(lua, []const u8, 1) }, false);
        return 0;
    }

    pub fn is_root(window: xzb.Window) bool {
        const tree = connection.queryTree(window);
        // catch |err| {
        //     log.err("Error querying tree for window {d}: {!}", .{ @enumToInt(window), err });
        //     return false;
        // };
        defer tree.destroy();
        return window == tree.root;
    }

    pub fn get_root() xzb.Window {
        const tree = connection.queryTree(get_focused_window());
        defer tree.destroy();
        return tree.root;
    }

    pub fn get_parent_window(window: xzb.Window) xzb.Window {
        const tree = connection.queryTree(window);
        defer tree.destroy();
        return if (tree.parent != tree.root and tree.parent != .none) tree.parent else window;
    }

    pub fn get_top_level_window(window: xzb.Window) xzb.Window {
        return connection.getTopLevelParent(window);
    }

    pub fn get_focused_window() xzb.Window {
        return connection.getInputFocus();
        // catch |err| {
        //     log.err("Error getting focused window: {!}", .{err});
        //     return .none;
        // };
    }

    pub fn get_geometry(lua: *Lua) i32 {
        lua.createTable(0, 5);

        const window = to(lua, xzb.Window, 1);
        if (window == .none) {
            log.err("Unexpected value for window!", .{});
            push(lua, @as(ziglua.Integer, 0));
            lua.setField(-2, "x");
            push(lua, @as(ziglua.Integer, 0));
            lua.setField(-2, "y");
            push(lua, @as(ziglua.Integer, 0));
            lua.setField(-2, "width");
            push(lua, @as(ziglua.Integer, 0));
            lua.setField(-2, "height");
            push(lua, @as(ziglua.Integer, 0));
            lua.setField(-2, "border_width");
            return 1;
        }

        const geometry = window.getGeometry(connection) catch |err| {
            log.err("Error getting window geometry: {!}", .{err});
            push(lua, @as(ziglua.Integer, 0));
            lua.setField(-2, "x");
            push(lua, @as(ziglua.Integer, 0));
            lua.setField(-2, "y");
            push(lua, @as(ziglua.Integer, 0));
            lua.setField(-2, "width");
            push(lua, @as(ziglua.Integer, 0));
            lua.setField(-2, "height");
            push(lua, @as(ziglua.Integer, 0));
            lua.setField(-2, "border_width");
            return 1;
        };

        push(lua, geometry.x);
        lua.setField(-2, "x");
        push(lua, geometry.y);
        lua.setField(-2, "y");
        push(lua, geometry.width);
        lua.setField(-2, "width");
        push(lua, geometry.height);
        lua.setField(-2, "height");
        push(lua, geometry.border_width);
        lua.setField(-2, "border_width");

        return 1;
    }

    pub fn get_title(lua: *Lua) i32 {
        const window = to(lua, xzb.Window, 1);
        if (window == .none) {
            log.err("Unexpected value for window!", .{});
            push(lua, @as([]const u8, ""));
            return 1;
        }

        const property_reply = window.getProperty(connection, false, .wm_name, xzb.Atom.any, 0, 128) catch |err| {
            log.err("Error getting window title: {!}", .{err});
            push(lua, @as([]const u8, ""));
            return 1;
        };
        defer xzb.destroy(property_reply);
        if (property_reply.value_len == 0) {
            push(lua, @as([]const u8, ""));
            return 1;
        }

        const pointer = property_reply.getValue() orelse {
            push(lua, @as([]const u8, ""));
            return 1;
        };
        const title = std.mem.span(@as([*:0]const u8, @ptrCast(pointer)));

        push(lua, title);
        return 1;
    }

    pub fn get_instance(lua: *Lua) i32 {
        const window = to(lua, xzb.Window, 1);
        if (window == .none) {
            log.err("Unexpected value for window!", .{});
            push(lua, @as([]const u8, ""));
            return 1;
        }
        const property_reply = window.getProperty(connection, false, .wm_class, xzb.Atom.any, 0, 128) catch |err| {
            log.err("Error getting window instance: {!}", .{err});
            return 0;
        };
        defer xzb.destroy(property_reply);
        if (property_reply.value_len == 0) {
            push(lua, @as([]const u8, ""));
            return 1;
        }

        const pointer = property_reply.getValue() orelse {
            push(lua, @as([]const u8, ""));
            return 1;
        };
        const instance = std.mem.span(@as([*:0]const u8, @ptrCast(pointer)));

        push(lua, instance);
        return 1;
    }

    pub fn get_class(lua: *Lua) i32 {
        const window = to(lua, xzb.Window, 1);
        if (window == .none) {
            log.err("Unexpected value for window!", .{});
            push(lua, @as([]const u8, ""));
            return 1;
        }
        const property_reply = window.getProperty(connection, false, .wm_class, xzb.Atom.any, 0, 128) catch |err| {
            log.err("Error getting window class: {!}", .{err});
            return 0;
        };
        defer xzb.destroy(property_reply);
        if (property_reply.value_len == 0) {
            push(lua, @as([]const u8, ""));
            return 1;
        }

        const pointer = property_reply.getValue() orelse {
            push(lua, @as([]const u8, ""));
            return 1;
        };
        var class_pointer: [*:0]const u8 = @ptrCast(pointer);
        const class = while (true) : (class_pointer += 1) {
            if (class_pointer[0] == '\x00') {
                class_pointer += 1;
                break std.mem.span(class_pointer);
            }
        };

        push(lua, class);
        return 1;
    }

    // pub fn _key_down(keysym: xzb.Keysym) void {
    //     const keycodes = symbols.getKeycode(connection, keysym) catch |err| {
    //         log.err("Error converting keysym to keycode: {!}", .{err});
    //         return;
    //     };
    //     if (keycodes.len == 0) {
    //         log.err("Invalid keysym value!", .{});
    //         return;
    //     }
    //     connection.fakeInput(.key_press, keycodes[0], .none, 0, 0, 0, .current) catch |err| {
    //         log.err("Error sending input: {!}", .{err});
    //     };
    //     connection.flush() catch {
    //         log.err("Error flushing to X server!", .{});
    //     };
    // }
    //
    // pub fn _key_up(keysym: xzb.Keysym) void {
    //     const keycodes = symbols.getKeycode(connection, keysym) catch |err| {
    //         log.err("Error converting keysym to keycode: {!}", .{err});
    //         return;
    //     };
    //     if (keycodes.len == 0) {
    //         log.err("Invalid keysym value!", .{});
    //         return;
    //     }
    //     connection.fakeInput(.key_release, keycodes[0], .none, 0, 0, 0, .current) catch |err| {
    //         log.err("Error sending input: {!}", .{err});
    //     };
    //     connection.flush() catch {
    //         log.err("Error flushing to X server!", .{});
    //     };
    // }

    // TODO: is this the best way to reload?
    pub fn reload(lua: *Lua) i32 {
        lua.pushNil();
        lua.setGlobal("lucky");
        unbindAll();

        loadApiAndConfig(lua) catch |err| {
            log.err("Error loading lua api or config: {!}", .{err});
        };

        return 0;
    }
};

// const lua_api =
//     \\function lucky.key_down(keysym)
//     \\    lucky._key_down(lucky.key[keysym])
//     \\end
//     \\
//     \\function lucky.key_up(keysym)
//     \\    lucky._key_up(lucky.key[keysym])
//     \\end
// ;

fn parseKey(
    keysym: xzb.Keysym,
    mod_mask: xzb.ModMask,
    pressed: bool,
    window: xzb.Window,
) bool {
    for (key_bindings.items) |binding| {
        const has_mod_mask = if (binding.mod_mask.hasAll(.{.any}))
            binding.mod_mask.hasAny(.{mod_mask}) or binding.mod_mask == .any
        else
            binding.mod_mask == mod_mask;
        if (binding.bind.key.value == keysym and has_mod_mask) {
            const filter_result = binding.testFilter(.{window}) catch |err| {
                log.err("Error running filter function: {!}", .{err});
                return false;
            };
            if (filter_result) {
                if (pressed) {
                    binding.press(.{window}) catch |err| {
                        log.err("Error calling press function: {!}", .{err});
                        return false;
                    };
                } else {
                    binding.release(.{window}) catch |err| {
                        log.err("Error calling release function: {!}", .{err});
                        return false;
                    };
                }
                return true;
            } else continue;
        }
    }
    return false;
}

fn parseButton(
    mouse_button: xzb.MouseButton,
    mod_mask: xzb.ModMask,
    pressed: bool,
    x: i16,
    y: i16,
    window: xzb.Window,
) struct { Binding, bool } {
    // TODO: ^ make this ?Binding instead
    for (button_bindings.items) |binding| {
        const has_mod_mask = if (binding.mod_mask.hasAll(.{.any}))
            binding.mod_mask.hasAny(.{mod_mask}) or binding.mod_mask == .any
        else
            binding.mod_mask == mod_mask;
        if (binding.bind.button.value == mouse_button and has_mod_mask) {
            const filter_result = binding.testFilter(.{ x, y, window }) catch |err| {
                log.err("Error running filter function: {!}", .{err});
                return .{ undefined, false };
            };
            if (filter_result) {
                if (pressed) {
                    binding.press(.{ x, y, window }) catch |err| {
                        log.err("Error calling press function: {!}", .{err});
                        return .{ undefined, false };
                    };
                } else {
                    binding.release(.{ x, y, window }) catch |err| {
                        log.err("Error calling release function: {!}", .{err});
                        return .{ undefined, false };
                    };
                }
                return .{ binding, true };
            } else continue;
        }
    }
    return .{ undefined, false };
}

// var state: State = undefined;

// TODO: bubble up errors, or add messages for them
fn to(lua: *Lua, comptime T: type, index: i32) T {
    switch (@typeInfo(T)) {
        .Int => {
            const int = lua.toInteger(index);
            return @intCast(int);
        },
        .Enum => |Enum| {
            const int = lua.toInteger(index);
            return @enumFromInt(@as(Enum.tag_type, @intCast(int)));
        },
        .Float => {
            const float = lua.toNumber(index) catch 0.0;
            return @floatCast(float);
        },
        .Bool => {
            const boolean = lua.toBoolean(index);
            return boolean;
        },
        .Pointer => |Pointer| {
            if (Pointer.size == .One) {
                compileError(
                    "Unsupported to type '{s}' for lua function!",
                    .{@typeName(T)},
                );
            } else if (Pointer.size == .Slice) {
                if (Pointer.child == u8) {
                    const string = lua.toBytes(index) catch "";
                    return string;
                } else {
                    compileError(
                        "Unsupported to type '{s}' for lua function!",
                        .{@typeName(T)},
                    );
                }
            } else {
                compileError(
                    "Unsupported to type '{s}' for lua function!",
                    .{@typeName(T)},
                );
            }
        },
        else => compileError(
            "Unsupported to type '{s}' for lua function!",
            .{@typeName(T)},
        ),
    }
}

fn push(lua: *Lua, value: anytype) void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .Fn => lua.pushFunction(wrap(value)),
        .Int => lua.pushInteger(@intCast(value)),
        .Enum => lua.pushInteger(@intCast(@intFromEnum(value))),
        .Float => lua.pushNumber(@floatCast(value)),
        .Bool => lua.pushBoolean(value),
        .Pointer => |Pointer| {
            if (Pointer.size == .Slice and Pointer.child == u8) {
                _ = lua.pushBytes(value);
            } else {
                compileError(
                    "Unsupported push type '{s}' for lua function!",
                    .{@typeName(T)},
                );
            }
        },
        .Type => {
            const info = @typeInfo(value);
            if (info != .Struct) {
                compileError(
                    "Unsupported push type '{s}' for lua function!",
                    .{@typeName(value)},
                );
            }
            createTable(lua, value);
        },
        .Void => {},
        else => compileError(
            "Unsupported return push '{s}' for lua function!",
            .{@typeName(T)},
        ),
    }
}

fn wrap(function: anytype) ziglua.CFn {
    switch (@TypeOf(function)) {
        ziglua.LuaState,
        ziglua.ZigFn,
        ziglua.ZigHookFn,
        ziglua.ZigContFn,
        ziglua.ZigReaderFn,
        ziglua.ZigWarnFn,
        ziglua.ZigWriterFn,
        => return ziglua.wrap(function),
        else => {},
    }

    const ArgsT = meta.ArgsTuple(@TypeOf(function));
    const ResultT = @typeInfo(@TypeOf(function)).Fn.return_type.?;
    const registerFn = struct {
        pub fn registerFn(l: *Lua) i32 {
            var args: ArgsT = undefined;
            inline for (meta.fields(ArgsT), 0..) |field, i| {
                args[i] = to(l, field.type, i + 1);
            }

            const result = @call(.always_inline, function, args);
            push(l, result);

            if (ResultT == void)
                return 0
            else
                return 1;
        }
    }.registerFn;
    return ziglua.wrap(registerFn);
}

fn register(lua: *Lua, name: [:0]const u8, function: anytype) void {
    lua.register(name, wrap(function));
}

fn GetFnType(comptime name: [:0]const u8, comptime signature: type) type {
    const ArgsT = meta.ArgsTuple(signature);
    const ResultT = @typeInfo(signature).Fn.return_type.?;
    const fields = meta.fields(ArgsT);
    const LuaFunctionWrapper = struct {
        lua: *Lua,

        pub fn call(self: @This(), args: ArgsT) !ResultT {
            self.lua.getGlobal(name) catch return error.MissingFn;
            inline for (0..fields.len) |i| {
                push(self.lua, args[i]);
            }
            if (ResultT != void) {
                try self.lua.protectedCall(fields.len, 1, 0);
                defer self.lua.pop(1);
                return to(self.lua, ResultT, -1);
            } else {
                try self.lua.protectedCall(fields.len, 0, 0);
            }
        }
    };
    return LuaFunctionWrapper;
}

fn getGlobalFn(lua: *Lua, comptime name: [:0]const u8, comptime signature: type) GetFnType(name, signature) {
    return GetFnType(name, signature){ .lua = lua };
}

fn createTable(lua: *Lua, source: anytype) void {
    const declarations = comptime meta.declarations(source);
    lua.createTable(0, declarations.len);
    inline for (declarations) |decl| {
        const value = @field(source, decl.name);
        push(lua, value);
        lua.setField(-2, decl.name ++ "\x00");
    }
}

fn unbindAll() void {
    key_bindings.clearAndFree();
    button_bindings.clearAndFree();
    connection.ungrabButton(.any, .any, screen.root);
    connection.ungrabKey(.any, .any, screen.root);
}

fn loadApiAndConfig(lua: *Lua) !void {
    @setEvalBranchQuota(5000);
    // TODO: module?
    createTable(lua, api);
    lua.setGlobal("lucky");

    // try lua.loadBuffer(lua_api, "lucky lua source");
    // lua.protectedCall(0, 0, 0) catch unreachable;

    lua.loadFile(config_path) catch |err| {
        log.err("{s}", .{to(lua, []const u8, -1)});
        switch (err) {
            error.File => return error.ConfigFileNotFound,
            else => return error.ConfigLoadError,
        }
    };

    lua.protectedCall(0, 0, 0) catch |err| {
        log.err("{s}", .{to(lua, []const u8, -1)});
        return err;
    };
}

var allocator: std.mem.Allocator = undefined;
var connection: *xzb.Connection = undefined;
var screen: xzb.Screen = undefined;
var symbols: *xzb.KeySymbols = undefined;
var function_register: i32 = undefined;
var key_bindings: std.ArrayList(Binding) = undefined;
var button_bindings: std.ArrayList(Binding) = undefined;
var config_path: [:0]const u8 = undefined;
var mouse_stack = std.BoundedArray(Binding.ButtonValue, 255).init(0) catch unreachable;
var hovered_window: xzb.Window = .none;
var motion_counter: usize = 0;

// TODO: remove error return, catch and log all errors and return with 1
pub fn main() anyerror!u8 {
    allocator = std.heap.c_allocator;

    var args_iterator = std.process.args();
    _ = args_iterator.skip();

    const options = try accord.parse(&.{
        accord.option('c', "config", ?[]const u8, null, .{}),
    }, allocator, &args_iterator);
    defer options.positionals.deinit(allocator);

    config_path = full_path: {
        if (options.config) |config| {
            break :full_path try allocator.dupeZ(u8, config);
        } else {
            const config_base_path = options.config orelse base_path: {
                const xdg_config_home = os.getenv("XDG_CONFIG_HOME");
                if (xdg_config_home) |path| {
                    break :base_path try mem.join(allocator, "/", &.{ path, "lucky" });
                } else {
                    const path = try mem.join(
                        allocator,
                        "/",
                        &.{ os.getenv("HOME").?, ".config" },
                    );
                    defer allocator.free(path);
                    break :base_path try mem.join(allocator, "/", &.{ path, "lucky" });
                }
            };
            defer allocator.free(config_base_path);
            break :full_path try mem.joinZ(allocator, "/", &.{ config_base_path, "config.lua" });
        }
    };
    defer allocator.free(config_path);

    key_bindings = std.ArrayList(Binding).init(allocator);
    defer key_bindings.clearAndFree();

    button_bindings = std.ArrayList(Binding).init(allocator);
    defer button_bindings.clearAndFree();

    var lua = try Lua.init(&allocator);
    defer lua.deinit();

    lua.newTable();
    function_register = try lua.ref(ziglua.registry_index);

    lua.openLibs();

    connection = try xzb.Connection.connect(null, null);

    var iterator = (try connection.getSetup()).rootsIterator();
    screen = iterator.next().?;

    symbols = try xzb.KeySymbols.alloc(connection);

    loadApiAndConfig(&lua) catch |err| switch (err) {
        error.ConfigFileNotFound => {
            log.err("File '{s}' not found!", .{config_path});
            return 1;
        },
        error.ConfigLoadError => {
            log.err("Unable to load file '{s}': {!}", .{ config_path, err });
            return 1;
        },
        else => {
            log.err("Error loading lua api or config: {!}", .{err});
            return 1;
        },
    };

    try connection.flush();

    // TODO: allow passing data into init?
    // getGlobalFn(&lua, "init", fn () void).call(.{}) catch |err| if (err != error.MissingFn) return err;

    while (true) {
        const event = connection.waitForEvent() catch continue;
        switch (event) {
            .button_press, .button_release => |button| {
                const pressed = event == .button_press;
                const pair = parseButton(
                    button.detail,
                    button.state.onlyKeys(),
                    pressed,
                    button.root_x,
                    button.root_y,
                    if (button.child != .none) button.child else button.root,
                );
                const binding = pair[0];
                const result = pair[1];

                if (result) {
                    if (pressed) {
                        mouse_stack.append(binding.bind.button) catch unreachable;
                    }
                    connection.allowEvents(.sync_pointer, .current);
                } else {
                    connection.allowEvents(.replay_pointer, .current);
                }

                if (!pressed) {
                    for (mouse_stack.constSlice(), 0..) |item, i| {
                        if (button.detail == item.value) {
                            _ = mouse_stack.orderedRemove(i);
                            if (mouse_stack.len == 0) {
                                hovered_window = .none;
                                motion_counter = 0;
                            }
                            break;
                        }
                    }
                }

                try connection.flush();
            },

            .motion_notify => |motion| {
                if (mouse_stack.len > 0) {
                    const window = if (motion.child != .none) motion.child else motion.root;
                    motion_counter += 1;
                    const button = mouse_stack.buffer[mouse_stack.len - 1];
                    if (motion_counter >= button.motion_resolution) {
                        motion_counter = 0;
                        button.motion(&lua, motion.root_x, motion.root_y, window) catch |err| {
                            log.err("Error calling motion function: {!}", .{err});
                        };
                    }
                    if (hovered_window != window) {
                        if (hovered_window != .none) {
                            button.exit(&lua, hovered_window) catch |err| {
                                log.err("Error calling exit function: {!}", .{err});
                            };
                        }
                        button.enter(&lua, window) catch |err| {
                            log.err("Error calling enter function: {!}", .{err});
                        };
                        hovered_window = window;
                    }
                }
            },

            .key_press, .key_release => |key| {
                const keysym = symbols.getKeysym(key.detail, 0);
                const result = parseKey(
                    keysym,
                    key.state.onlyKeys(),
                    event == .key_press,
                    if (key.child != .none) key.child else key.root,
                );

                if (result) {
                    connection.allowEvents(.sync_keyboard, .current);
                } else {
                    connection.allowEvents(.replay_keyboard, .current);
                }

                try connection.flush();
            },
            else => {},
        }
    }

    return 0;
}
