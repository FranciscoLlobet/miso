const std = @import("std");
const microzig = @import("microzig");

const MicroBuild = microzig.MicroBuild(.{
    .efm32 = true,
});

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse return;

    const available_examples = [_]Example{
        .{ .target = mb.ports.efm32.chips.efm32gg390f1024, .name = "EFM32GG390", .file = "src/main.zig" },
    };

    for (available_examples) |example| {
        // `add_firmware` basically works like addExecutable, but takes a
        // `microzig.Target` for target instead of a `std.zig.CrossTarget`.
        //
        // The target will convey all necessary information on the chip,
        // cpu and potentially the board as well.
        const fw = mb.add_firmware(.{
            .name = example.name,
            .target = example.target,
            .optimize = optimize,
            .root_source_file = b.path(example.file),
        });

        const package = b.dependency("miso/csrc", .{
            .optimize = optimize,
        });

        //fw.add_app_import(name: []const u8, module: *Build.Module, options: AppDependencyOptions)
        fw.add_app_import("miso/csrc", package.module("board"), .{});
        //fw.add_app_import("leds", package.module("leds"), .{});

        // Link towards the C-Src artifact
        fw.add_object_file(package.artifact("csrc").getEmittedBin());

        const freertos_package = b.dependency("freertos", .{ .optimize = optimize });
        const freertos = freertos_package.module("freertos");
        fw.add_app_import("freertos", freertos, .{});
        fw.add_object_file(freertos_package.artifact("freertos").getEmittedBin());

        // Adding precompiled Lib-C
        fw.add_object_file(b.path("picolibc/clang-compiled/picolibc/libc.a"));

        // This will also install into `$prefix/firmware` instead of `$prefix/bin`.
        mb.install_firmware(fw, .{ .format = .bin });

        // For debugging, we also always install the firmware as an ELF file
        mb.install_firmware(fw, .{ .format = .elf });
    }
}

const Example = struct {
    target: *const microzig.Target,
    name: []const u8,
    file: []const u8,
};
