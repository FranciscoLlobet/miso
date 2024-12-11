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
        .name = "mqtt",
        .target = target,
        .optimize = optimize,
    });

    //const freertos = b.dependency("freertos", .{});
    const board = b.dependency("board", .{});

    for (source_path) |p| {
        lib.addCSourceFile(.{ .file = b.path(p), .flags = &c_flags });
    }

    for (include_path) |p| {
        lib.addIncludePath(b.path(p));
    }
    for (include_path) |p| {
        lib.installHeadersDirectory(b.path(p), "mqtt/include", .{});
    }

    //lib.addIncludePath(freertos.artifact("freertos").getEmittedIncludeTree().path(b, "freertos/include"));
    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "config/include"));
    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "board/include"));
    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "picolib/include"));

    // Process modules
    const board_module = b.addModule("mqtt", .{
        .root_source_file = b.path("src/mqtt.zig"),
        .target = target,
        .optimize = optimize,
    });

    board_module.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "config/include"));
    board_module.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "picolib/include"));
    for (include_path) |p| {
        board_module.addIncludePath(b.path(p));
    }

    b.installArtifact(lib);
}

const include_path = [_][]const u8{
    "paho.mqtt.embedded-c/MQTTPacket/src/",
};

const paho_src_path = "paho.mqtt.embedded-c/MQTTPacket/src/";

const source_path = [_][]const u8{
    paho_src_path ++ "MQTTFormat.c",
    paho_src_path ++ "MQTTPacket.c",
    paho_src_path ++ "MQTTSerializePublish.c",
    paho_src_path ++ "MQTTDeserializePublish.c",
    paho_src_path ++ "MQTTConnectClient.c",
    paho_src_path ++ "MQTTSubscribeClient.c",
    paho_src_path ++ "MQTTUnsubscribeClient.c",
};

const c_flags = [_][]const u8{ "-DMQTT_CLIENT=1", "-O2", "-fdata-sections", "-ffunction-sections" };
