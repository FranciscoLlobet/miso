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
        .name = "freertos", // freertos
        .target = target,
        .optimize = optimize,
    });

    const board = b.dependency("board", .{});

    for (source_paths) |p| {
        lib.addCSourceFile(.{ .file = b.path(p), .flags = &c_flags });
    }

    for (include_path) |p| {
        lib.addIncludePath(b.path(p));
    }

    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "config/include"));
    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "picolib/include"));

    // Process modules
    const freertos_module = b.addModule("freertos", .{
        .root_source_file = b.path("src/freertos.zig"),
        .target = target,
        .optimize = optimize,
    });

    freertos_module.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "config/include"));
    freertos_module.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "picolib/include"));

    for (include_path) |p| {
        freertos_module.addIncludePath(b.path(p));
    }

    lib.installHeadersDirectory(b.path("FreeRTOS-Kernel/include"), "freertos/include", .{});
    lib.installHeadersDirectory(b.path("FreeRTOS-Kernel/portable/GCC/ARM_CM3"), "freertos/include", .{});

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);
}

const c_flags = [_][]const u8{ "-DEFM32GG390F1024", "-O2", "-DSL_CATALOG_POWER_MANAGER_PRESENT=1", "-fdata-sections", "-ffunction-sections" };

const include_path = [_][]const u8{
    // FreeRTOS
    "FreeRTOS-Kernel/include",
    "FreeRTOS-Kernel/portable/GCC/ARM_CM3",
};

const source_paths = [_][]const u8{
    "FreeRTOS-Kernel/croutine.c",
    "FreeRTOS-Kernel/list.c",
    "FreeRTOS-Kernel/queue.c",
    "FreeRTOS-Kernel/stream_buffer.c",
    "FreeRTOS-Kernel/tasks.c",
    "FreeRTOS-Kernel/timers.c",
    "FreeRTOS-Kernel/portable/GCC/ARM_CM3/port.c",
    "FreeRTOS-Kernel/portable/MemMang/heap_4.c",
};
