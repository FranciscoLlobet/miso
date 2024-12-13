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
        .name = "fatfs", // freertos
        .target = target,
        .optimize = optimize,
    });

    for (source_paths) |p| {
        lib.addCSourceFile(.{ .file = b.path(p), .flags = &c_flags });
    }

    for (include_path) |p| {
        lib.addIncludePath(b.path(p));
    }

    lib.addIncludePath(b.path("../ext/gecko_sdk/platform/emlib/inc"));
    lib.addIncludePath(b.path("../board/inc"));
    lib.addIncludePath(b.path("../config"));
    lib.addSystemIncludePath(b.path("../../picolibc/clang-compiled/picolibc/include"));

    lib.installHeadersDirectory(b.path("ff15/source"), "fatfs/include", .{});

    // Process modules
    const board_module = b.addModule("fatfs", .{
        .root_source_file = b.path("src/fatfs.zig"),
        .target = target,
        .optimize = optimize,
    });

    board_module.addIncludePath(b.path("../board/inc"));
    board_module.addIncludePath(b.path("../config"));
    for (include_path) |p| {
        board_module.addIncludePath(b.path(p));
    }

    //lib.installHeader(b.path("board/inc/board.h"), "board.h");

    board_module.addSystemIncludePath(b.path("../../picolibc/clang-compiled/picolibc/include"));
    //board_module.addIncludePath(b.path("config"));

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);
}

const c_flags = [_][]const u8{ "-DEFM32GG390F1024", "-O2", "-fdata-sections", "-ffunction-sections" };

const include_path = [_][]const u8{
    "ff15/source",
};

const source_paths = [_][]const u8{
    "ff15/source/ff.c",
    "ff15/source/ffunicode.c",
};
