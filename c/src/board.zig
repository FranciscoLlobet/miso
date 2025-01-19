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
    mcuReset();

    unreachable;
}

pub fn mcuReset() noreturn {
    c.BOARD_MCU_Reset();
    unreachable;
}

pub fn watchdogEnable() void {
    c.BOARD_Watchdog_Enable();
}

pub fn watchdogFeed() void {
    c.BOARD_Watchdog_Feed();
}

pub fn watchdogDisable() void {
    c.BOARD_Watchdog_Disable();
}

/// Get local time
pub fn getTime() u32 {
    return c.sl_sleeptimer_get_time();
}

/// Get local Ntp time
pub fn getNtpTime() u32 {
    var ntp_time: u32 = undefined;

    return if (c.SL_STATUS_OK == c.sl_sleeptimer_convert_unix_time_to_ntp(c.sl_sleeptimer_get_time(), &ntp_time)) ntp_time else 0;
}

/// Set local time from NTP time
pub fn setTimeFromNtp(ntp_time: u32) !void {
    var time_stamp: u32 = undefined;

    var rc: c.sl_status_t = undefined;
    rc = c.sl_sleeptimer_convert_ntp_time_to_unix(ntp_time, &time_stamp);

    if (c.SL_STATUS_OK == rc) {
        rc = c.sl_sleeptimer_set_time(time_stamp);
    }

    if (c.SL_STATUS_OK != rc) {
        //return error.UnexpectedError;
    }

    //var sl_date: c.sl_sleeptimer_date_t = undefined;

    //if (c.SL_STATUS_OK == c.sl_sleeptimer_get_datetime(&sl_date)) {
    //   var simple_link_date: c.SlDateTime_t = undefined;

    //     simple_link_date.sl_tm_day = sl_date.month_day;
    //     simple_link_date.sl_tm_mon = sl_date.month + 1;
    //     simple_link_date.sl_tm_year = sl_date.year + 1900;
    //     simple_link_date.sl_tm_hour = sl_date.hour;
    //     simple_link_date.sl_tm_min = sl_date.min;
    //       simple_link_date.sl_tm_sec = sl_date.sec;

    //      if (0 > c.sl_DevSet(c.SL_DEVICE_GENERAL_CONFIGURATION, c.SL_DEVICE_GENERAL_CONFIGURATION_DATE_TIME, @sizeOf(@TypeOf(simple_link_date)), @ptrCast(&simple_link_date))) {
    //          //
    //      }
    //  } else {
    //      // return
    //  }
}

pub fn calculateDeadline(timeout_s: u32) u32 {
    return getTime() + timeout_s;
}
