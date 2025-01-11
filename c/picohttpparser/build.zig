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
        .name = "picohttpparser",
        .target = target,
        .optimize = optimize,
    });

    const board = b.dependency("board", .{});

    for (source_path) |p| {
        lib.addCSourceFile(.{ .file = b.path(p), .flags = &c_flags });
    }

    for (include_path) |p| {
        lib.addIncludePath(b.path(p));
    }
    for (include_path) |p| {
        lib.installHeadersDirectory(b.path(p), "picohttpparser/include", .{});
    }

    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "picolib/include"));

    // Process modules
    const board_module = b.addModule("picohttpparser", .{
        .root_source_file = b.path("src/picohttpparser.zig"),
        .target = target,
        .optimize = optimize,
    });

    for (include_path) |p| {
        board_module.addIncludePath(b.path(p));
    }

    board_module.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "picolib/include"));

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);
}

const include_path = [_][]const u8{"picohttpparser"};

const source_path = [_][]const u8{"picohttpparser/picohttpparser.c"};

const c_flags = [_][]const u8{ "-O2", "-fdata-sections", "-ffunction-sections" };
