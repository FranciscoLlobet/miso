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
const http = @import("http.zig");

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

/// NTP Sync Time
ntpSyncTime: u32,

/// State
state: state,

fn myNtpTimerFunction(self: *@This()) void {
    self.task.notify(@intFromEnum(notificationValues.ntp_sync), .eSetBits) catch {};
}

fn myUserTaskFunction(self: *@This()) noreturn {
    // Initialize the NVM
    _ = nvm.init() catch 0;

    fatfs.mount("SD") catch unreachable;

    while (true) {
        const current_state = self.state;
        //       var next_state: state = undefined;

        self.state = switch (current_state) {
            .verify_config => verify_config(),
            .start_connectivity => self.start_connectivity(),
            .start_ntp_time => self.start_ntp_time(),
            .perform_firmware_download => self.perform_firmware_download(),
            .start_mqtt => .start_mqtt,
            else => .verify_config,
        };
        //next_state;
    }

    unreachable;
}

/// Verify configuration activity
fn verify_config() state {
    config.load_config_from_nvm() catch {};

    _ = config.open_config_file(config.config_file_name) catch {};

    return state.start_connectivity;
}

fn start_connectivity(self: *@This()) state {
    const wifi_task = freertos.Task.initFromHandle(@as(freertos.TaskHandle_t, @ptrCast(c.wifi_task_handle)));

    // Start the WiFi task
    wifi_task.resumeTask();

    while (self.task.waitForNotify(0, @intFromEnum(notificationValues.connectivity_on), null) catch unreachable) |val| {
        if (notificationValues.isNotification(val, notificationValues.connectivity_on)) {
            break;
        }
    }

    return state.start_ntp_time;
}

fn start_ntp_time(self: *@This()) state {
    const ntp_uri: std.Uri = std.Uri.parse("ntp://1.de.pool.ntp.org:123") catch unreachable;

    const originate_timestamp_s: u32 = board.getNtpTime();
    //const originate_timestamp_frac: u32 = 0;

    if (ntp.getTimeFromServer(ntp_uri, originate_timestamp_s, 0)) |ntpResponse| {

        // Store last ntp sync time
        self.ntpSyncTime = ntpResponse.timestamp_s;

        // Set the NTP time on board
        try board.setTimeFromNtp(ntpResponse.timestamp_s);

        // Calculate the next time to sync
        const nextSyncTime: u32 = if (ntpResponse.poll_interval > 60 * 60) @as(u32, 60 * 60 * 1000) else ntpResponse.poll_interval * 1000;

        _ = c.printf("NTP Sync: %u\r\n", ntpResponse.timestamp_s);

        self.ntpTimer.changePeriod(nextSyncTime, null) catch unreachable;

        return state.perform_firmware_download;
    } else |_| {
        // Error response
        self.task.delayTask(16000); // wait for 16
        return state.start_ntp_time; // unnecessary
    }
}

fn perform_firmware_download(self: *@This()) state {
    _ = c.printf("Performing firmware download\r\n");

    if (downloadAndVerify()) |_| {
        // Happy path

        //nvm.setUpdateRequest() catch unreachable;

        _ = c.printf("Firmware download complete\r\n");

        self.task.delayTask(1000);

        // reset
    } else |_| {
        // Error path
        _ = c.printf("Firmware download failed\r\n");
        // reset
    }

    return state.start_mqtt;
}

fn downloadAndVerify() !bool {
    // Download the firmware
    try http.service.filedownload(config.getHttpFwUri(), config.fw_file_name, config.file_block_size, 1024 * 1024);

    //try firmware.checkFirmwareImage(config.fw_file_name);

    return true;
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
    .ntpSyncTime = undefined,
};

pub export fn miso_notify_event(event: c.miso_event) callconv(.C) void {
    userTask.task.notify(event, .eSetBits) catch {};
}
