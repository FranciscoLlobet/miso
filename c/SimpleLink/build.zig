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
        .name = "simplelink", // freertos
        .target = target,
        .optimize = optimize,
    });

    const freertos = b.dependency("freertos", .{});
    const board = b.dependency("board", .{});

    for (source_paths) |p| {
        lib.addCSourceFile(.{ .file = b.path(p), .flags = &c_flags });
    }

    for (include_path) |p| {
        lib.addIncludePath(b.path(p));
    }
    for (include_path) |p| {
        lib.installHeadersDirectory(b.path(p), "simplelink/include", .{});
    }

    lib.addIncludePath(freertos.artifact("freertos").getEmittedIncludeTree().path(b, "freertos/include"));
    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "config/include"));
    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "board/include"));
    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "picolib/include"));
    //lib.addSystemIncludePath(b.path("../../picolibc/clang-compiled/picolibc/include"));

    // Process modules
    const board_module = b.addModule("simplelink", .{
        .root_source_file = b.path("src/simplelink.zig"),
        .target = target,
        .optimize = optimize,
    });

    board_module.addIncludePath(b.path("../config"));
    for (include_path) |p| {
        board_module.addIncludePath(b.path(p));
    }

    //lib.installHeader(b.path("board/inc/board.h"), "board.h");

    //board_module.addSystemIncludePath(b.path("../../picolibc/clang-compiled/picolibc/include"));
    //board_module.addIncludePath(b.path("config"));

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);
}

const c_flags = [_][]const u8{ "-O0", "-DEFM32GG390F1024", "-D__OSI__=1", "-D__SL__", "-fdata-sections", "-ffunction-sections" };

const include_path = [_][]const u8{
    "cc3100-sdk/simplelink/include",
    "cc3100-sdk/oslib",
    "cc3100-sdk/netapps",
};

const source_paths = [_][]const u8{
    "cc3100-sdk/oslib/osi_freertos.c",
    "cc3100-sdk/simplelink/source/device.c",
    "cc3100-sdk/simplelink/source/driver.c",
    "cc3100-sdk/simplelink/source/flowcont.c",
    "cc3100-sdk/simplelink/source/fs.c",
    "cc3100-sdk/simplelink/source/netapp.c",
    "cc3100-sdk/simplelink/source/netcfg.c",
    "cc3100-sdk/simplelink/source/nonos.c",
    "cc3100-sdk/simplelink/source/socket.c",
    "cc3100-sdk/simplelink/source/spawn.c",
    "cc3100-sdk/simplelink/source/wlan.c",
};
