const std = @import("std");
const microzig_build = @import("microzig/build");

fn root() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

const KiB: usize = 1024;
const build_root = root();

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    _ = b.step("test", "Run unit tests");
}

/// Bootloader target for the EFM32GG390 chip on the XDK110 development kit.
pub const xdk110 = microzig_build.Target{
    .preferred_format = .elf,
    .chip = .{
        .name = "EFM32GG390F1024",
        .cpu = microzig_build.cpus.cortex_m3,
        .register_definition = .{
            .svd = .{ .cwd_relative = build_root ++ "/src/chips/EFM32GG390F1024.svd" },
        },
        .memory_regions = &.{
            .{ .offset = 0x00000000, .length = 1024 * KiB, .kind = .flash },
            .{ .offset = 0x20000000, .length = 128 * KiB, .kind = .ram },
        },
    },
    .hal = .{
        .root_source_file = .{ .cwd_relative = build_root ++ "/src/hals/xdk110.zig" },
    },
};
