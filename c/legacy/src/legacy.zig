const std = @import("std");
pub const c = @cImport({
    @cInclude("miso.h");
    @cInclude("network.h");
    @cInclude("miso_config.h");
    @cInclude("wifi_service.h");

    //@cInclude("wifi_service.h");
    //@cInclude("lwm2m_client.h");
});

pub const nvm = @import("nvm.zig");
pub const network = @import("network.zig");
pub const connection = @import("connection.zig");
pub const simpleConnection = @import("simpleConnection.zig");

const create_network_mediator = connection.create_network_mediator;
const suspend_network_mediator = connection.suspend_network_mediator;
const resume_network_mediator = connection.resume_network_mediator;
const network_mediator_wait_rx = connection.network_mediator_wait_rx;
