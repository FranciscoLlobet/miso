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

    const board = b.dependency("board", .{});

    // Process modules
    const jsmn_module = b.addModule("jsmn", .{
        .root_source_file = b.path("src/jsmn.zig"),
        .target = target,
        .optimize = optimize,
    });

    //jsmn_module.add
    jsmn_module.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "picolibc/include"));

    for (include_path) |p| {
        jsmn_module.addIncludePath(b.path(p));
    }
}

const include_path = [_][]const u8{"jsmn"};

const c_flags = [_][]const u8{ "-O2", "-fdata-sections", "-ffunction-sections" };
