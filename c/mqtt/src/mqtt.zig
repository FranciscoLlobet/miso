const std = @import("std");

pub const c = @cImport({
    @cDefine("MQTT_CLIENT", "1");
    @cInclude("MQTTPacket.h");
});
