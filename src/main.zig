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

const board = @import("miso/csrc");

pub fn main() noreturn {
    //

    board.init();

    while (true) { //
        // microzig.hal.leds.orange.on();
    }

    unreachable;
}

pub fn init() void {
    // SystemInit();
}

pub fn GPIO_EVEN() callconv(.C) void {
    //c.GPIO_EVEN_IRQHandler();
}
pub fn GPIO_ODD() callconv(.C) void {
    // c.GPIO_ODD_IRQHandler();
}
pub fn RTC() callconv(.C) void {
    // c.RTC_IRQHandler();
}
pub fn DMA() callconv(.C) void {
    //c.DMA_IRQHandler();
}
pub fn I2C0() callconv(.C) void {
    //c.I2C0_IRQHandler();
}
pub fn USB() callconv(.C) void {
    // c.USB_IRQHandler();
}
pub fn TIMER0() callconv(.C) void {
    // c.TIMER0_IRQHandler();
}
pub fn SysTick() callconv(.C) void {
    //
}
/// Redirecting the PendSV to the FreeRTOS handler
//pub const PendSV = xPortPendSVHandler;

/// Redirecting the SVCall to the FreeRTOS handler
//pub const SVCall = vPortSVCHandler;

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
        .GPIO_EVEN = Handler{ .C = GPIO_EVEN },
        .GPIO_ODD = Handler{ .C = GPIO_ODD },
        .RTC = Handler{ .C = RTC },
        .DMA = Handler{ .C = DMA },
        .I2C0 = Handler{ .C = I2C0 },
        .USB = Handler{ .C = USB },
        .TIMER0 = Handler{ .C = TIMER0 },
        .SysTick = Handler{ .C = SysTick },
    },
};
