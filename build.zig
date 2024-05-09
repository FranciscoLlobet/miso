const std = @import("std");
const microzig_build = @import("microzig/build");
const xdk110 = @import("bsp/xdk110");

const variants = [_]Variant{
    .{ .name = "firmware", .target = xdk110.xdk110, .root_source_file = "src/main.zig" },
};

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const microzig = microzig_build.init(b, .{});

    for (variants) |variant| {
        const firmware = microzig.add_firmware(b, .{
            .name = variant.name,
            .target = variant.target,
            .optimize = optimize,
            .root_source_file = .{ .path = variant.root_source_file },
        });

        microzig.install_firmware(b, firmware, .{});
    }
}

const Variant = struct {
    target: microzig_build.Target,
    name: []const u8,
    root_source_file: []const u8,
};
