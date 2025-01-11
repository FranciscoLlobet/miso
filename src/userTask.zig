const std = @import("std");
const microzig = @import("microzig");

const board = @import("board");
const freertos = @import("freertos");
const leds = board.leds;
const legacy = @import("legacy");
const nvm = legacy.nvm;
const c = legacy.c;
const network = legacy.network;
const fatfs = @import("fatfs");

const ntp = @import("ntp.zig");
const config = @import("config.zig");

const state = enum(usize) {
    verify_config = 0,
    start_connectivity,
    stop_connectivity,

    /// First NTP sync
    start_ntp_time,
    start_mqtt,
    start_lwm2m,
    get_config,
    perform_firmware_download,
    verify_firmware_download,

    working, // normal work mode
};

const notificationValues = enum(u32) {
    no = 0,

    connectivity_on = c.miso_connectivity_on,
    connectivity_off = c.miso_connectivity_off,

    ntp_sync = c.miso_ntp_sync,
    user_timer = c.miso_user_timer,

    //lwm2m_suspended = c.miso_lwm2m_suspended,

    pub fn isNotification(val: u32, notification: notificationValues) bool {
        return (val & @intFromEnum(notification)) == @intFromEnum(notification);
    }
};

/// User task handle
task: freertos.StaticTask(@This(), config.rtos_stack_depth_user_task, "user task", myUserTaskFunction),

/// NTP Timer
ntpTimer: freertos.StaticTimer(@This(), "ntp timer", myNtpTimerFunction),

/// State
state: state,

const wifi_task = freertos.Task.initFromHandle(@as(freertos.TaskHandle_t, @ptrCast(c.wifi_task_handle)));

fn myNtpTimerFunction(self: *@This()) void {
    self.task.notify(@intFromEnum(notificationValues.ntp_sync), .eSetBits) catch {};
}

fn myUserTaskFunction(self: *@This()) noreturn {

    // Initialize the NVM
    _ = nvm.init() catch 0;

    fatfs.mount("SD") catch unreachable;

    while (true) {
        if (self.state == .verify_config) {
            config.load_config_from_nvm() catch {};

            _ = config.open_config_file(config.config_file_name) catch {};

            //board
        } else {
            //;
        }
    }

    unreachable;
}

pub fn create(self: *@This()) void {
    self.state = state.verify_config;
    self.task.create(self, config.rtos_prio_user_task) catch unreachable;
    //self.timer.create(2000, true, self) catch unreachable;
    self.ntpTimer.create(4000, true, self) catch unreachable;
    //self.ntpSyncTime = 0;
}

pub var userTask: @This() = .{
    .task = undefined,
    .ntpTimer = undefined,
    .state = undefined,
};
