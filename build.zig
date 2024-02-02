const std = @import("std");

pub fn getBuildMode(b: *std.Build, default: std.builtin.Mode) !std.builtin.Mode {
    const description = try std.mem.join(b.allocator, "", &.{
        "What optimization mode the project should build in (default: ", @tagName(default), ")",
    });
    const mode = b.option(std.builtin.Mode, "optimize", description) orelse default;

    return mode;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = try getBuildMode(b, .ReleaseFast);
    // const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const lucky = b.addExecutable(.{
        .name = "lucky",
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = optimize,
        .target = target,
    });

    // TODO: consider changing to 5.1, for a future in which luajit has bindings
    const ziglua = b.dependency("ziglua", .{ .lang = .luajit });
    lucky.root_module.addImport("ziglua", ziglua.module("ziglua"));
    lucky.root_module.addImport("accord", b.dependency("accord", .{}).module("accord"));
    lucky.root_module.addImport("xzb", b.dependency("xzb", .{}).module("xzb"));

    lucky.linkLibrary(ziglua.artifact("lua"));
    lucky.linkSystemLibrary("xcb");
    lucky.linkSystemLibrary("xcb-keysyms");
    // lucky.linkSystemLibrary("xcb-xtest");

    b.installArtifact(lucky);

    const run_cmd = b.addRunArtifact(lucky);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
