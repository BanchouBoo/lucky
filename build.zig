const std = @import("std");
const ziglua = @import("pkg/ziglua/build.zig");

pub fn getBuildMode(b: *std.build.Builder, default: std.builtin.Mode) !std.builtin.Mode {
    const description = try std.mem.join(b.allocator, "", &.{
        "What optimization mode the project should build in (default: ", @tagName(default), ")",
    });
    const mode = b.option(std.builtin.Mode, "optimize", description) orelse default;

    return mode;
}

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = try getBuildMode(b, .ReleaseFast);
    // const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const lucky = b.addExecutable(.{
        .name = "lucky",
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = optimize,
        .target = target,
    });

    lucky.addAnonymousModule("accord", .{ .source_file = .{ .path = "pkg/accord/accord.zig" } });
    lucky.addAnonymousModule("xzb", .{ .source_file = .{ .path = "pkg/xzb/xzb.zig" } });
    // TODO: consider changing to 5.1, for a future in which luajit has bindings
    lucky.addModule("ziglua", ziglua.linkAndPackage(b, lucky, .{ .version = .lua_54 })); // this links libc

    lucky.linkSystemLibrary("xcb");
    lucky.linkSystemLibrary("xcb-keysyms");
    // lucky.linkSystemLibrary("xcb-xtest");

    lucky.install();

    const run_cmd = lucky.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
