const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    //const target = b.standardTargetOptions(.{});

    // Overiding the target for practice
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = .{
            .explicit = &std.Target.arm.cpu.cortex_m3,
        },
        .os_tag = .freestanding,
        .abi = .eabi,
    });

    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "legacy", // freertos
        .target = target,
        .optimize = optimize,
    });

    //b.dependencyFromBuildZig(comptime build_zig: type, args: anytype)
    const simplelink = b.dependency("simplelink", .{ .optimize = optimize });
    const freertos = b.dependency("freertos", .{ .optimize = optimize });
    const board = b.dependency("board", .{ .optimize = optimize });
    const fatfs = b.dependency("fatfs", .{ .optimize = optimize });
    const mbedtls = b.dependency("mbedtls", .{ .optimize = optimize });
    const jsmn = b.dependency("jsmn", .{ .optimize = optimize });

    for (source_paths) |p| {
        lib.addCSourceFile(.{ .file = b.path(p), .flags = &c_flags });
    }

    for (include_path) |p| {
        lib.addIncludePath(b.path(p));
    }
    for (include_path) |p| {
        lib.installHeadersDirectory(b.path(p), "legacy/include", .{});
    }
    lib.addIncludePath(jsmn.path("jsmn"));
    lib.addIncludePath(mbedtls.artifact("mbedtls").getEmittedIncludeTree().path(b, "mbedtls/include"));
    lib.addIncludePath(fatfs.artifact("fatfs").getEmittedIncludeTree().path(b, "fatfs/include"));
    lib.addIncludePath(simplelink.artifact("simplelink").getEmittedIncludeTree().path(b, "simplelink/include"));
    lib.addIncludePath(freertos.artifact("freertos").getEmittedIncludeTree().path(b, "freertos/include"));
    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "config/include"));
    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "board/include"));
    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "picolib/include"));
    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "emlib/include"));
    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "cmsis/include"));
    // Process modules
    const board_module = b.addModule("legacy", .{
        .root_source_file = b.path("src/legacy.zig"),
        .target = target,
        .optimize = optimize,
    });

    board_module.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "config/include"));
    board_module.addIncludePath(mbedtls.artifact("mbedtls").getEmittedIncludeTree().path(b, "mbedtls/include"));
    board_module.addIncludePath(fatfs.artifact("fatfs").getEmittedIncludeTree().path(b, "fatfs/include"));
    board_module.addIncludePath(simplelink.artifact("simplelink").getEmittedIncludeTree().path(b, "simplelink/include"));
    board_module.addIncludePath(freertos.artifact("freertos").getEmittedIncludeTree().path(b, "freertos/include"));
    board_module.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "board/include"));
    board_module.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "picolib/include"));
    board_module.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "emlib/include"));
    board_module.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "cmsis/include"));
    for (include_path) |p| {
        board_module.addIncludePath(b.path(p));
    }

    board_module.addImport("freertos", freertos.module("freertos"));
    board_module.addImport("mbedtls", mbedtls.module("mbedtls"));
    b.installArtifact(lib);
}

const c_flags = [_][]const u8{ "-DMBEDTLS_CONFIG_FILE=\"miso_mbedtls_config.h\"", "-O2", "-DEFM32GG390F1024", "-DSL_CATALOG_POWER_MANAGER_PRESENT=1", "-fdata-sections", "-ffunction-sections", "-DMISO_APPLICATION" };

const include_path = [_][]const u8{
    "inc",
};

const source_paths = [_][]const u8{
    "src/config.c",
    "src/wifi_service.c",
    "src/mbedtls_adapter/entropy.c",
    "src/mbedtls_adapter/timing.c",
    "src/mbedtls_adapter/threading.c",
};
