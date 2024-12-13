// Copyright (c) 2023-2024 Francisco Llobet-Blandino and the "Miso Project".
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the “Software”), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

const std = @import("std");
const microzig = @import("microzig");

const board = @import("board");
const freertos = @import("freertos");
const leds = board.leds;
const legacy = @import("legacy");
const nvm = legacy.nvm;
const c = legacy.c;
const network = legacy.network;

// Enable or Disable features at compile time
pub const enable_lwm2m = false;
pub const enable_mqtt = true;
pub const enable_http = true;

/// Export the NVM3 handle
pub export const miso_nvm3_handle = &nvm.miso_nvm3;
pub export const miso_nvm3_init_handle = &nvm.miso_nvm3_init;

pub fn main() noreturn {
    //
    const appCounter: u32 = nvm.incrementAppCounter() catch 0;

    board.init();

    network.start();

    _ = c.printf("--- MISO starting FreeRTOS %d---\n\r", appCounter);

    freertos.vTaskStartScheduler();

    unreachable;
}

pub fn init() void {
    // SystemInit();
}

export fn vApplicationIdleHook() void {
    //  board.watchdogFeed();
}

export fn vApplicationDaemonTaskStartupHook() void {
    leds.red.on();

    board.msDelay(500);

    leds.orange.on();

    board.msDelay(500);

    leds.yellow.on();

    board.msDelay(500);

    leds.red.off();

    board.msDelay(500);

    leds.orange.off();

    board.msDelay(500);

    leds.yellow.off();
}

export fn vApplicationStackOverflowHook() noreturn {
    microzig.hang();
}

export fn vApplicationMallocFailedHook() noreturn {
    microzig.hang();
}

export fn vApplicationTickHook() void {
    //
}

export fn vApplicationGetRandomHeapCanary(pxHeapCanary: [*c]u32) void {
    pxHeapCanary.* = @as(u32, 0xdeadbeef);
}

export fn hang() callconv(.C) void {
    microzig.hang();
}

pub fn SysTick() callconv(.C) void {
    if (.taskSCHEDULER_NOT_STARTED != freertos.xTaskGetSchedulerState()) {
        freertos.xPortSysTickHandler();
    }
}

pub fn HardFault() callconv(.C) void {
    microzig.hang(); //c_board.BOARD_MCU_Reset();
}
pub fn MemManageFault() callconv(.C) void {
    microzig.hang(); //c_board.BOARD_MCU_Reset();
}

pub fn BusFault() callconv(.C) void {
    microzig.hang();
}

pub fn UsageFault() callconv(.C) void {
    microzig.hang();
}

const Handler = microzig.interrupt.Handler;

pub const microzig_options = .{
    .interrupts = .{
        .HardFault = Handler{ .C = HardFault },
        .MemManageFault = Handler{ .C = MemManageFault },
        .BusFault = Handler{ .C = BusFault },
        .UsageFault = Handler{ .C = UsageFault },
        .GPIO_EVEN = Handler{ .C = board.GPIO_EVEN_IRQHandler },
        .GPIO_ODD = Handler{ .C = board.GPIO_ODD_IRQHandler },
        .RTC = Handler{ .C = board.RTC_IRQHandler },
        .DMA = Handler{ .C = board.DMA_IRQHandler },
        .I2C0 = Handler{ .C = board.I2C0_IRQHandler },
        .USB = Handler{ .C = board.USB_IRQHandler },
        .TIMER0 = Handler{ .C = board.TIMER0_IRQHandler },
        .SysTick = Handler{ .C = SysTick },
        .PendSV = Handler{ .Naked = freertos.xPortPendSVHandler },
        .SVCall = Handler{ .Naked = freertos.vPortSVCHandler },
    },
};
