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

        const package = b.dependency("board", .{
            .optimize = optimize,
        });

        //fw.add_app_import(name: []const u8, module: *Build.Module, options: AppDependencyOptions)
        fw.add_app_import("board", package.module("board"), .{});

        // Link towards the C-Src artifact
        fw.add_object_file(package.artifact("board").getEmittedBin());

        // FreeRTOS
        const freertos_package = b.dependency("freertos", .{ .optimize = optimize });
        const freertos = freertos_package.module("freertos");
        fw.add_app_import("freertos", freertos, .{});
        fw.add_object_file(freertos_package.artifact("freertos").getEmittedBin());

        // FatFS
        const fatfs_package = b.dependency("fatfs", .{ .optimize = optimize });
        const fatfs = fatfs_package.module("fatfs");
        fw.add_app_import("fatfs", fatfs, .{});
        fw.add_object_file(fatfs_package.artifact("fatfs").getEmittedBin());

        // SimpleLink
        const simplelink_package = b.dependency("simplelink", .{ .optimize = optimize });
        const simplelink = simplelink_package.module("simplelink");
        fw.add_app_import("simplelink", simplelink, .{});
        fw.add_object_file(simplelink_package.artifact("simplelink").getEmittedBin());

        // Picohttpparser
        const picohttpparser_package = b.dependency("picohttpparser", .{ .optimize = optimize });
        const picohttpparser = picohttpparser_package.module("picohttpparser");
        fw.add_app_import("picohttpparser", picohttpparser, .{});
        fw.add_object_file(picohttpparser_package.artifact("picohttpparser").getEmittedBin());

        // Mqtt
        const mqtt_package = b.dependency("mqtt", .{ .optimize = optimize });
        const mqtt = mqtt_package.module("mqtt");
        fw.add_app_import("mqtt", mqtt, .{});
        fw.add_object_file(mqtt_package.artifact("mqtt").getEmittedBin());

        // mbedTLS
        const mbedtls_package = b.dependency("mbedtls", .{ .optimize = optimize });
        const mbedtls = mbedtls_package.module("mbedtls");
        fw.add_app_import("mbedtls", mbedtls, .{});
        fw.add_object_file(mbedtls_package.artifact("mbedtls").getEmittedBin());

        // Legacy
        const legacy_package = b.dependency("legacy", .{ .optimize = optimize });
        const legacy = legacy_package.module("legacy");
        fw.add_app_import("legacy", legacy, .{});
        fw.add_object_file(legacy_package.artifact("legacy").getEmittedBin());

        // Adding precompiled Lib-C
        fw.add_object_file(b.path("picolibc/clang-compiled/picolibc/libc.a"));
        fw.add_object_file(b.path("c/ext/gecko_sdk/platform/emdrv/nvm3/lib/libnvm3_CM3_gcc.a"));

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
