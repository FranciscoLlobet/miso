const std = @import("std");
pub const leds = @import("leds.zig");
const c = @import("csrc.zig").c;

pub export fn init() void {
    c.BOARD_Init();
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
