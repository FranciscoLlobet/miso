const std = @import("std");

pub const c = @cImport({
    @cDefine("MQTT_CLIENT", "1");
    @cInclude("string.h");
    @cInclude("MQTTPacket.h");
});

pub const mqtt_error = error{
    packetlen,
    enqueue_failed,
    dequeue_failed,
    connect_failed,
    send_failed,
    connack_failed,
    parse_failed,
    publish_parse_failed,
    subscribe_qos_topic_count_mismatch, // The number of topics and qos do not match
    qos_not_supported,

    qos_packet_not_found,
    pubrel_packet_not_found,
    qos_packet_timeout,
};

/// Quality of Service
pub const QoS = enum(c_int) {
    qos0 = 0,
    qos1 = 1,
    qos2 = 2,

    fn fromInt(x: c_int) !QoS {
        return switch (x) {
            0 => .qos0,
            1 => .qos1,
            2 => .qos2,
            else => mqtt_error.qos_not_supported,
        };
    }
};

pub const MQTTTransport = c.MQTTTransport;
pub const MQTTString = c.MQTTString;
pub const MQTTLenString = c.MQTTLenString;

/// MQTT OK return code
/// Used internally to check the return code of the MQTTPacket functions
pub const mqtt_ok: c_int = 1;

/// Message types from MQTTPacket
pub const msgTypes = enum(c_int) { err_msg = -1, try_again = 0, connect = c.CONNECT, connack = c.CONNACK, publish = c.PUBLISH, puback = c.PUBACK, pubrec = c.PUBREC, pubrel = c.PUBREL, pubcomp = c.PUBCOMP, subscribe = c.SUBSCRIBE, suback = c.SUBACK, unsubscribe = c.UNSUBSCRIBE, unsuback = c.UNSUBACK, pingreq = c.PINGREQ, pingresp = c.PINGRESP, disconnect = c.DISCONNECT };

const keepAliveInterval_s = 60;
const keepAliveInterval_ms = 1000 * keepAliveInterval_s;

/// MQTT String initializer
pub const MQTTString_initializer = MQTTString{
    .cstring = null,
    .lenstring = .{ .len = 0, .data = null },
};

/// Init a MQTT String using slice.
/// Has been tested in comptime
pub inline fn initMQTTString(data: ?[]const u8) MQTTString {
    if (data) |val| {
        return MQTTString{ .cstring = null, .lenstring = .{ .len = @intCast(val.len), .data = @constCast(val.ptr) } };
    } else {
        return MQTTString_initializer;
    }
}

/// Get MQTT String as slice
pub inline fn getMQTTString(data: MQTTString) []u8 {
    if (data.cstring) |cstring| {
        return cstring[0..c.strlen(cstring)];
    } else if ((data.lenstring.data != null) and (data.lenstring.len > 0)) {
        return data.lenstring.data[0..@intCast(data.lenstring.len)];
    } else {
        return undefined;
    }
}

/// Manually translated initializer
pub const MQTTPacket_willOptions_initializer = c.MQTTPacket_willOptions{
    .struct_id = [_]u8{ 'M', 'Q', 'T', 'W' },
    .struct_version = 0,
    .topicName = MQTTString_initializer,
    .message = MQTTString_initializer,
    .retained = 0,
    .qos = 0,
};

/// Manually translated initializer
pub const MQTTPacket_connectData_initializer = c.MQTTPacket_connectData{
    .struct_id = [_]u8{ 'M', 'Q', 'T', 'C' },
    .struct_version = 0,
    .MQTTVersion = 4,
    .clientID = MQTTString_initializer,
    .keepAliveInterval = 0,
    .cleansession = 1,
    .willFlag = 0,
    .will = MQTTPacket_willOptions_initializer,
    .username = MQTTString_initializer,
    .password = MQTTString_initializer,
};

/// Publish packet response
pub const publish_response = struct {
    packetId: u16,
    qos: QoS,
    dup: bool,
    retained: bool,
    topic: []u8,
    payload: []u8,
};

/// Check the output of the MQTTSerialize_xyz functions for error returns and avoids buffer overflows
/// Returns a slice of the workBuffer
fn serializeCheck(workBuffer: []u8, packetLen: isize) ![]u8 {
    if (packetLen <= 0) {
        return mqtt_error.packetlen; // Could not serialize packet
    } else if (packetLen > workBuffer.len) {
        return mqtt_error.packetlen; // Packet too big
    } else {
        return workBuffer[0..@intCast(packetLen)]; // Reslice the buffer to the packet length
    }
}

/// Deserialize a publish packet from buffer and converts it into a `publish_response`
pub fn deserializePublish(buffer: []const u8) !publish_response {
    var topicName = MQTTString_initializer;
    var payload: [*c]u8 = undefined;
    var payloadLen: isize = undefined;
    var packetId: u16 = 0;
    var retained: u8 = undefined;
    var dup: u8 = undefined;
    var qos: c_int = undefined;

    if (mqtt_ok != c.MQTTDeserialize_publish(&dup, &qos, &retained, &packetId, &topicName, &payload, &payloadLen, @constCast(buffer.ptr), @intCast(buffer.len))) {
        return mqtt_error.parse_failed;
    }

    const retQos = try QoS.fromInt(qos);

    return publish_response{ .packetId = packetId, .qos = retQos, .dup = (if (dup == 0) false else true), .retained = (if (retained == 0) false else true), .topic = getMQTTString(topicName), .payload = payload[0..@intCast(payloadLen)] };
}

pub fn deserializePuback(buffer: []const u8) !struct { packetId: u16, dup: bool } {
    var packetId: u16 = undefined;
    var dup: u8 = undefined;
    var packetType: u8 = undefined;

    if (mqtt_ok != c.MQTTDeserialize_ack(&packetType, &dup, &packetId, @constCast(buffer.ptr), @intCast(buffer.len))) {
        return mqtt_error.parse_failed;
    }
    if (packetType != c.PUBACK) {
        return mqtt_error.parse_failed; // Not actually a puback when expected
    }
    return .{ .packetId = packetId, .dup = (if (dup == 0) false else true) };
}

/// Deserialize a pubrel packet from buffer
pub fn deserializePubrel(buffer: []const u8) !struct { packetId: u16, dup: bool } {
    var packetId: u16 = undefined;
    var dup: u8 = undefined;
    var packetType: u8 = undefined;

    if (mqtt_ok != c.MQTTDeserialize_ack(&packetType, &dup, &packetId, @constCast(buffer.ptr), @intCast(buffer.len))) {
        return mqtt_error.parse_failed;
    }
    if (packetType != c.PUBREL) {
        return mqtt_error.parse_failed; // Not actually a pubrel when expected
    }
    return .{ .packetId = packetId, .dup = (if (dup == 0) false else true) };
}

/// Deserialize a pubrec packet from buffer
pub fn deserializePubrec(buffer: []const u8) !u16 {
    var packetId: u16 = undefined;
    var dup: u8 = undefined;
    var packetType: u8 = undefined;

    if (mqtt_ok != c.MQTTDeserialize_ack(&packetType, &dup, &packetId, @constCast(buffer.ptr), @intCast(buffer.len))) {
        return mqtt_error.parse_failed;
    }
    if (packetType != c.PUBREC) {
        return mqtt_error.parse_failed; // Not actually a pubrec when expected
    }

    return packetId;
}

/// Deserialize a pubcomp packet from buffer
pub fn deserializePubcomp(buffer: []const u8) !u16 {
    var packetId: u16 = undefined;
    var dup: u8 = undefined;
    var packetType: u8 = undefined;

    if (mqtt_ok != c.MQTTDeserialize_ack(&packetType, &dup, &packetId, @constCast(buffer.ptr), @intCast(buffer.len))) {
        return mqtt_error.parse_failed;
    }
    if (packetType != c.PUBCOMP) {
        return mqtt_error.parse_failed; // Not actually a pubcomp when expected
    }

    return packetId;
}

/// Deserialize a suback packet from buffer
pub fn deserializeSubAck(buffer: []const u8, qos: []QoS) !struct { packetId: u16, qos: []QoS } {
    var packetId: u16 = undefined;
    var count: c_int = 0;

    if (mqtt_ok != c.MQTTDeserialize_suback(&packetId, @intCast(qos.len), &count, @ptrCast(qos.ptr), @constCast(buffer.ptr), @intCast(buffer.len))) {
        return mqtt_error.parse_failed;
    }
    return .{ .packetId = packetId, .qos = qos[0..@as(usize, @intCast(count))] };
}

/// Process the connack packet
pub fn processConnAck(buffer: []u8) !void {
    var sessionPresent: u8 = undefined;
    var connack_rc: u8 = undefined;

    if (mqtt_ok == c.MQTTDeserialize_connack(&sessionPresent, &connack_rc, @ptrCast(buffer.ptr), @intCast(buffer.len))) {
        if (connack_rc != c.MQTT_CONNECTION_ACCEPTED) {
            return mqtt_error.connack_failed;
        }
    } else {
        return mqtt_error.parse_failed;
    }
}

pub const serialization_result = struct {
    buffer: []u8,
    packetId: ?u16,
};

pub fn serializePuback(workBuffer: []u8, packetId: u16) !serialization_result {
    return .{
        .buffer = try serializeCheck(workBuffer, c.MQTTSerialize_puback(@ptrCast(workBuffer.ptr), @intCast(workBuffer.len), packetId)),
        .packetId = packetId,
    };
}

pub fn serializePublish(workBuffer: []u8, topic: []const u8, payload: []const u8, qos: QoS, dup: bool, packetId: u16) !serialization_result {
    const topic_name = initMQTTString(topic);
    const retain: u8 = 0;

    return .{
        .buffer = try serializeCheck(workBuffer, c.MQTTSerialize_publish(workBuffer.ptr, @intCast(workBuffer.len), @intCast(@intFromBool(dup)), @intFromEnum(qos), retain, packetId, topic_name, @constCast(payload.ptr), @intCast(payload.len))),
        .packetId = packetId,
    };
}

pub fn serializePubrec(workBuffer: []u8, packetId: u16) !serialization_result {
    return .{
        .buffer = try serializeCheck(workBuffer, c.MQTTSerialize_pubrec(workBuffer.ptr, @intCast(workBuffer.len), packetId)),
        .packetId = packetId,
    };
}

pub fn serializePubComp(workBuffer: []u8, packetId: u16) !serialization_result {
    return .{
        .buffer = try serializeCheck(workBuffer, c.MQTTSerialize_pubcomp(workBuffer.ptr, @intCast(workBuffer.len), packetId)),
        .packetId = packetId,
    };
}

pub fn serializePubRel(workBuffer: []u8, packetId: u16, dup: bool) !serialization_result {
    return .{
        .buffer = try serializeCheck(workBuffer, c.MQTTSerialize_pubrel(workBuffer.ptr, @intCast(workBuffer.len), @intCast(@intFromBool(dup)), packetId)),
        .packetId = packetId,
    };
}

pub fn serializeSubscribe(workBuffer: []u8, topicFilter: []MQTTString, qos: []QoS, packetId: u16) !serialization_result {
    const count = if (topicFilter.len == qos.len) topicFilter.len else return mqtt_error.subscribe_qos_topic_count_mismatch;
    const dup: u8 = 0;

    return .{
        .buffer = try serializeCheck(workBuffer, c.MQTTSerialize_subscribe(workBuffer.ptr, @intCast(workBuffer.len), dup, packetId, @intCast(count), topicFilter.ptr, @ptrCast(qos.ptr))),
        .packetId = packetId,
    };
}

pub fn serializePingReq(workBuffer: []u8) !serialization_result {
    return .{
        .buffer = try serializeCheck(workBuffer, c.MQTTSerialize_pingreq(workBuffer.ptr, @intCast(workBuffer.len))),
        .packetId = null,
    };
}

pub fn serializeDisconnect(workBuffer: []u8) !serialization_result {
    return .{
        .buffer = try serializeCheck(workBuffer, c.MQTTSerialize_disconnect(workBuffer.ptr, @intCast(workBuffer.len))),
        .packetId = null,
    };
}

pub fn serializeConnect(workBuffer: []u8, clientID: []const u8, username: ?[]const u8, password: ?[]const u8) !serialization_result {
    var connectPacket = MQTTPacket_connectData_initializer;

    connectPacket.clientID = initMQTTString(clientID);
    connectPacket.username = initMQTTString(username);
    connectPacket.password = initMQTTString(password);
    connectPacket.keepAliveInterval = 400;

    return .{
        .buffer = try serializeCheck(workBuffer, c.MQTTSerialize_connect(workBuffer.ptr, @intCast(workBuffer.len), &connectPacket)),
        .packetId = null,
    };
}
