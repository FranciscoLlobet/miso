const std = @import("std");
//const Build = std.Build;
//const LazyPath = Build.LazyPath;
const microzig = @import("microzig/build-internals");

const Self = @This();

const KiB : usize = 1024;
const RAM_SIZE : usize = 128 * KiB;
const FLASH_SIZE : usize = 1024 * KiB;

chips: struct{
    efm32gg390f1024 : *const microzig.Target,
},

boards: struct{}

pub fn init(dep: *std.Build.Dependency) Self{
    const b = dep.builder;

    const chip_efm32gg390f1024 : microzig.Target = .{
        .dep = dep,
        .preferred_binary_format = .elf,
        .chip = .{
            .name = "EFM32GG390F1024",
            .cpu = .{
                .cpu_arch = .thumb,
                .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m3 },
                .os_tag = .freestanding,
                .abi = .eabi,
            }
            .register_definition = .{ .zig = b.path("EFM32GG390F1024.zig")},
            .memory_regions = &.{
                .{ .offset = 0x00000000, .length = FLASH_SIZE, .kind = .flash }, 
                .{ .offset = 0x20000000, .length = RAM_SIZE, .kind = .ram }, // RAM
            },
        },
    };

    return .{
        .chips = .{
            .efm32gg390f1024 = chip_efm32gg390f1024.derive(.{}),
        },
        .boards = .{},
    }


} 
