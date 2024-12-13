const std = @import("std");
pub const leds = @import("leds.zig");
pub const buttons = @import("buttons.zig");
const c = @import("csrc.zig").c;

pub export fn init() void {
    c.BOARD_Init();
}

pub fn msDelay(ms: u32) void {
    c.BOARD_msDelay(ms);
}

pub fn usDelay(us: u32) void {
    c.BOARD_usDelay(us);
}

pub const bma280_dev = &c.board_bma280;
pub const bme280_dev = &c.board_bme280;
pub const bmg160_dev = &c.board_bmg160;
pub const bmi160_dev = &c.board_bmi160;
pub const bmm150_dev = &c.board_bmm150;

pub const button1 = &c.button1;
pub const button2 = &c.button2;

pub const led_red = &c.led_red;
pub const led_orange = &c.led_orange;
pub const led_yellow = &c.led_yellow;

// Expose Board IRQ Handlers
pub const GPIO_EVEN_IRQHandler = c.GPIO_EVEN_IRQHandler;
pub const GPIO_ODD_IRQHandler = c.GPIO_ODD_IRQHandler;
pub const RTC_IRQHandler = c.RTC_IRQHandler;
pub const DMA_IRQHandler = c.DMA_IRQHandler;
pub const I2C0_IRQHandler = c.I2C0_IRQHandler;
pub const USB_IRQHandler = c.USB_IRQHandler;
pub const TIMER0_IRQHandler = c.TIMER0_IRQHandler;

// Button On-Change Callback
pub export fn sl_button_on_change(handle: buttons.button_handle) callconv(.C) void {
    const instance = buttons.getInstance(handle);
    const state = instance.getState();
    switch (instance.getName()) {
        .button1 => {
            switch (state) {
                .pressed => {
                    leds.red.on();
                },
                .released => {
                    leds.red.off();
                },
                else => {},
            }
        },
        .button2 => {
            switch (state) {
                .pressed => {
                    leds.orange.on();
                },
                .released => {
                    leds.orange.off();
                },
                else => {},
            }
        },
    }
}

pub export fn system_reset() callconv(.C) void {
    unreachable;
}
