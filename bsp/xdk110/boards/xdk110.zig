const std = @import("std");
const microzig = @import("microzig");
pub const c = @cImport({
    @cInclude("board.h");
    //@cInclude("simplelink.h");
    //@cInclude("board_i2c_sensors.h");
});

pub const button1 = &c.button1;
pub const button2 = &c.button2;

pub const led_red = &c.led_red;
pub const led_orange = &c.led_orange;
pub const led_yellow = &c.led_yellow;
