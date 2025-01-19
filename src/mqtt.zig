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

/// Basic MQTT Client implementation in Zig using FreeRTOS as OS
/// This is a work in progress and is not ready for production use
///
/// Not all aspects of the MQTT state machine were implemented
/// QoS 2 is partially supported
///
const std = @import("std");
const freertos = @import("freertos");
const config = @import("config.zig");
const system = @import("board");
const legacy = @import("legacy");
const connection = legacy.connection;
const simpleConnection = legacy.simpleConnection;
const tls = legacy.tls;
const mbedtls = @import("mbedtls");
const mqtt = @import("mqtt");

const c = mqtt.c;

const keepAliveInterval_s = 60;
const keepAliveInterval_ms = 1000 * keepAliveInterval_s;

const state = enum(i32) {
    err = -1,
    not_connected = 0,
    connecting,
    connected,
    disconnecting,
};

//// Mqtt Error codes
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

/// Publish response type
const packet_response = @This().packet.publish_response;

const fw_update_topic = "zig/fw";
const conf_update_topic = "zig/conf";
const reset_topic = "zig/reset";

const connectionType = connection.Connection(tls.TlsContext(@This(), simpleConnection.SimpleLinkConnection(.tls_ip4), .psk));

const QoS = mqtt.QoS;
const msgTypes = mqtt.msgTypes;

connection: connectionType,
connectionCounter: usize,
disconnectionCounter: usize,
pingCounter: usize,

pingTimer: freertos.StaticTimer(@This(), "pingTimer", pingTimer),
pubTimer: freertos.StaticTimer(@This(), "pubTimer", pubTimer),

task: freertos.StaticTask(@This(), config.rtos_stack_depth_mqtt, "mqtt", if (config.enable_mqtt) taskFunction else dummyTaskFunction),
state: state,
packet: @This().packet,
uri_string: [*:0]u8,
device_id: [*:0]u8,

/// Qos1 tx queue
qosQueue: QueuedMessgeQueue,

/// QoS2 rx queue
qos2Queue: QueuedMessgeQueue,

/// Ping message queue
pingQueue: freertos.StaticQueue(freertos.TickType_t, 1),

var txBuffer: [256]u8 align(@alignOf(u32)) = undefined;
var rxBuffer: [512]u8 align(@alignOf(u32)) = undefined;
var workBuffer: [256]u8 align(@alignOf(u32)) = undefined;

fn init() @This() {
    return @This(){
        .connection = undefined,
        .connectionCounter = 0,
        .disconnectionCounter = 0,
        .pingTimer = undefined,
        .pubTimer = undefined,
        .task = undefined,
        .state = .not_connected,
        .packet = packet.init(),
        .uri_string = undefined,
        .device_id = undefined,
        .qosQueue = QueuedMessgeQueue.init(freertos.allocator),
        .qos2Queue = QueuedMessgeQueue.init(freertos.allocator),
        .pingCounter = 0,
        .pingQueue = undefined,
    };
}

/// Authentification callback for mbedTLS connections
fn authCallback(self: *@This(), security_mode: connection.security_mode) tls.auth_error!void {
    if (security_mode == .psk) {
        var psk_buf: [64]u8 = undefined; // Request 64 Bytes for Base64 decoder

        const psk = mbedtls.base64Decode(legacy.c.config_get_mqtt_psk_key(), &psk_buf) catch return tls.auth_error.generic_error;
        self.connection.ssl.confPsk(psk, legacy.c.config_get_mqtt_psk_id()) catch return tls.auth_error.generic_error;

        @memset(&psk_buf, 0); // Sanitize the buffer to avoid the decoded psk to remain in stack
    } else {
        return tls.auth_error.unsuported_mode;
    }
}

/// Process and send the contents of the txQueue
fn processSendQueue(self: *@This()) !void {
    while (self.packet.txQueue.receive(&txBuffer, 0)) |buf| {
        _ = try self.connection.send(buf);
    }
}

/// Queued message
const QueuedMessage = struct {
    packetId: ?u16,
    qos: QoS,
    dup: bool,
    retained: bool,
    topic: []u8,
    payload: []u8,
    deadline: u32,
    packetType: msgTypes,
};

/// Queued Message Queue
const QueuedMessgeQueue = struct {
    /// Message Queue
    message: std.ArrayList(QueuedMessage),

    /// Comptime Initializer
    pub fn init(comptime allocator: std.mem.Allocator) @This() {
        return @This(){ .message = std.ArrayList(QueuedMessage).init(allocator) };
    }

    /// Add a message to the queue
    pub fn addPublish(self: *@This(), packetId: u16, qos: QoS, dup: bool, retained: bool, topic: []const u8, payload: []const u8, deadline: u32) !void {
        const new_payload = try self.message.allocator.alloc(u8, payload.len);
        const new_topic = try self.message.allocator.alloc(u8, topic.len);

        @memcpy(new_payload, payload);
        @memcpy(new_topic, topic);

        try self.message.append(QueuedMessage{ .packetId = packetId, .qos = qos, .dup = dup, .retained = retained, .topic = new_topic, .payload = new_payload, .deadline = deadline, .packetType = .publish });
    }

    /// Add a pubrel message to the queue
    pub fn addPubRel(self: *@This(), packetId: u16, dup: bool, deadline: u32) !void {
        try self.message.append(QueuedMessage{ .packetId = packetId, .qos = .qos2, .dup = dup, .retained = false, .topic = undefined, .payload = undefined, .deadline = deadline, .packetType = .pubrel });
    }

    /// Scan the queue for messages that match the packetId
    pub fn acknowledge(self: *@This(), packetId: u16, packetType: msgTypes) !bool {
        for (self.message.items, 0..) |*item, idx| {
            if (item.packetId) |id| {
                if ((id == packetId) and (item.packetType == packetType)) {
                    // Remove the message from the list
                    const msg = self.message.orderedRemove(idx);

                    if (msg.packetType == .publish) {
                        // Clear topic and payload content
                        @memset(msg.topic, 0);
                        @memset(msg.payload, 0);

                        self.message.allocator.free(msg.topic);
                        self.message.allocator.free(msg.payload);
                    } else {
                        _ = c.printf("pubrel removed: %d\r\n", msg.packetId.?);
                    }

                    return true;
                }
            }
        }
        return false;
    }

    /// Remove all messages that have expired
    pub fn prune(self: *@This()) ?QueuedMessage {
        for (self.message.items, 0..) |*item, idx| {
            if (item.deadline < system.getTime()) {
                return self.message.orderedRemove(idx);
            }
        }
        return null;
    }

    /// Find and remove a message from the queue
    pub fn findAndRemove(self: *@This(), packetId: u16) ?QueuedMessage {
        for (self.message.items, 0..) |*item, idx| {
            if (item.packetId) |id| {
                if (id == packetId) {
                    return self.message.orderedRemove(idx);
                }
            }
        }
        return null;
    }
};

const packet = struct {
    transport: mqtt.MQTTTransport,
    packetIdState: u16,
    workBufferMutex: freertos.StaticMutex(),
    txQueue: freertos.StaticMessageBuffer(1024),

    pub fn init() @This() {
        return @This(){ .transport = .{
            .getfn = getFn,
            .sck = undefined,
            .multiplier = undefined,
            .rem_len = undefined,
            .len = undefined,
            .state = undefined,
        }, .packetIdState = 1, .workBufferMutex = undefined, .txQueue = undefined };
    }

    pub fn create(self: *@This(), conn: *connectionType) void {
        self.transport.sck = @ptrCast(conn);

        self.workBufferMutex.create() catch unreachable;

        self.txQueue.create() catch unreachable; // Create message buffer
    }

    /// Generate Packet ID using pseudo random number generator
    ///
    /// Uses XorShift Algorithm to generate the packet id
    fn generatePacketId(self: *@This()) u16 {
        if (self.packetIdState != 0) {
            self.packetIdState ^= self.packetIdState << 7;
            self.packetIdState ^= self.packetIdState >> 9;
            self.packetIdState ^= self.packetIdState << 8;
        } else {
            self.packetIdState = 1;
        }

        return self.packetIdState;
    }

    /// Get function for the MQTTTransport
    fn getFn(ptr: ?*anyopaque, buf: [*c]u8, buf_len: c_int) callconv(.C) c_int {
        const self = @as(*connectionType, @ptrCast(@alignCast(ptr))); // Cast ptr as connection

        const ret = self.recieve(buf[0..@intCast(buf_len)]) catch {
            return @intFromEnum(msgTypes.err_msg);
        };

        return @intCast(ret.len);
    }

    /// Read from the transport layer
    /// Uses the non-blocking (NB) version of the MQTTPacket read function
    fn read(self: *@This(), buffer: []u8) msgTypes {
        self.transport.state = 0;
        return @as(msgTypes, @enumFromInt(c.MQTTPacket_readnb(@ptrCast(&buffer[0]), @intCast(buffer.len), &self.transport)));
    }

    /// Prepare a connect packet
    fn prepareConnectPacket(self: *@This(), clientID: []const u8, username: ?[]const u8, password: ?[]const u8) !u16 {
        _ = try self.workBufferMutex.take(null);
        defer self.workBufferMutex.give() catch {};

        const sr = try mqtt.serializeConnect(&workBuffer, clientID, username, password);

        return self.sendtoTxQueue(sr.buffer, sr.packetId);
    }

    /// Prepare the puback packet and sends to TX Queue
    fn preparePubAckPacket(self: *@This(), packetId: u16) !u16 {
        _ = try self.workBufferMutex.take(null);
        defer self.workBufferMutex.give() catch {};

        const sr = try mqtt.serializePuback(&workBuffer, packetId);

        return self.sendtoTxQueue(sr.buffer, sr.packetId);
    }

    /// Prepare the pubrec packet and sends to TX Queue
    fn preparePubRecPacket(self: *@This(), packetId: u16) !u16 {
        _ = try self.workBufferMutex.take(null);
        defer self.workBufferMutex.give() catch {};

        const sr = try mqtt.serializePubrec(&workBuffer, packetId);

        return self.sendtoTxQueue(sr.buffer, sr.packetId);
    }

    /// Prepare the pubcomp packet and sends to TX Queue
    fn preparePubCompPacket(self: *@This(), packetId: u16) !u16 {
        _ = try self.workBufferMutex.take(null);
        defer self.workBufferMutex.give() catch {};

        const sr = try mqtt.serializePubComp(&workBuffer, packetId);

        return self.sendtoTxQueue(sr.buffer, sr.packetId);
    }

    /// Prepare the `pubrel` packet and sends to TX Queue
    fn preparePubRelPacket(self: *@This(), packetId: u16, dup: bool) !u16 {
        _ = try self.workBufferMutex.take(null);
        defer self.workBufferMutex.give() catch {};

        const sr = try mqtt.serializePubRel(&workBuffer, packetId, dup);

        return self.sendtoTxQueue(sr.buffer, sr.packetId);
    }

    /// Prepare the subscribe packet and sends to TX Queue
    /// Both topicFilter and qos must have the same length
    fn prepareSubscribePacket(self: *@This(), topicFilter: []mqtt.MQTTString, qos: []QoS) !u16 {
        _ = try self.workBufferMutex.take(null);
        defer self.workBufferMutex.give() catch {};

        const packetId = self.generatePacketId();
        const sr = try mqtt.serializeSubscribe(&workBuffer, topicFilter, qos, packetId);

        return self.sendtoTxQueue(sr.buffer, sr.packetId);
    }

    /// Prepare a ping packet and sends to TX Queue
    fn preparePingPacket(self: *@This()) !u16 {
        _ = try self.workBufferMutex.take(null);
        defer self.workBufferMutex.give() catch {};

        const sr = try mqtt.serializePingReq(&workBuffer);

        return self.sendtoTxQueue(sr.buffer, sr.packetId);
    }

    /// prepare a disconnect packet and sends to TX Queue
    fn prepareDisconnectPacket(self: *@This()) !u16 {
        _ = try self.workBufferMutex.take(null);
        defer self.workBufferMutex.give() catch {};

        const sr = try mqtt.serializeDisconnect(&workBuffer);

        return self.sendtoTxQueue(sr.buffer, sr.packetId);
    }

    /// Prepare a publish packet and sends to TX Queue
    pub fn preparePublishPacket(self: *@This(), topic: []const u8, payload: []const u8, qos: QoS, dup: bool, packetId: ?u16) !u16 {
        _ = try self.workBufferMutex.take(null);
        defer self.workBufferMutex.give() catch {};

        const id = packetId orelse self.generatePacketId();

        const sr = try mqtt.serializePublish(&workBuffer, topic, payload, qos, dup, id);

        return self.sendtoTxQueue(sr.buffer, sr.packetId);
    }

    /// Send the content of the buffer to the txQueue.
    /// The optional packet ID is propagated to the next layer if the operation was successful
    fn sendtoTxQueue(self: *@This(), buffer: []u8, packetId: ?u16) !u16 {
        if (buffer.len != self.txQueue.send(buffer, null)) {
            return mqtt_error.enqueue_failed;
        }

        return @intCast(packetId orelse 0);
    }
};

fn loop(self: *@This(), uri: std.Uri) !void {
    try self.connect(uri);
    defer self.disconnect() catch {};

    while (true) {
        const current_cycle_time = freertos.xTaskGetTickCount(); // Get current cycle time
        _ = current_cycle_time;

        // process the QoS1 tx queue
        while (self.qosQueue.prune()) |msg| {
            switch (msg.packetType) {
                .publish => {
                    try self.publish(msg.topic, msg.payload, msg.qos, true, msg.packetId, system.calculateDeadline(2000));
                },
                .pubrel => {
                    const ret = try self.packet.preparePubRelPacket(msg.packetId.?, true);
                    try self.qosQueue.addPubRel(ret, true, system.calculateDeadline(2000));
                },
                else => {},
            }
        }

        // process the QoS2 rx queue
        while (self.qos2Queue.prune()) |msg| {
            @memset(msg.topic, 0);
            @memset(msg.payload, 0);
            self.qos2Queue.message.allocator.free(msg.topic);
            self.qos2Queue.message.allocator.free(msg.payload);
        }

        try self.processSendQueue();

        // Think if I make this into a while
        while (self.connection.waitRx(1) catch false) {
            const readRet = self.packet.read(&rxBuffer);
            switch (readRet) {
                .try_again => {},
                .publish => {
                    const publish_response = try mqtt.deserializePublish(&rxBuffer);

                    // prepare the response packets depwnding on the QOS
                    const packetId: u16 = switch (publish_response.qos) {
                        .qos0 => publish_response.packetId,
                        .qos1 => try self.packet.preparePubAckPacket(publish_response.packetId),
                        .qos2 => try self.packet.preparePubRecPacket(publish_response.packetId),
                    };

                    // Immediatly send the ACK to the broker in case of QOS 1
                    if (publish_response.qos == .qos1) {
                        try self.processSendQueue();
                    }

                    if (publish_response.qos != .qos2) {
                        // If QOS is 0 or 1, then we can send the message to the application layer
                        var buf: [64]u8 = undefined;
                        @memset(&buf, 0);

                        if (std.mem.eql(u8, publish_response.topic[0..fw_update_topic.len], fw_update_topic)) {
                            // FW trigger
                            //try user.user_task.task.notify(0xA, .eSetBits);
                            //system.reset();
                            //self.task.suspendTask();
                            break;
                        }

                        const s = try std.fmt.bufPrint(&buf, "publish recieved: {d}, {d} {s} {s}\r\n", .{ packetId, @intFromEnum(publish_response.qos), publish_response.topic, publish_response.payload });

                        _ = c.printf("%s", s.ptr);
                    } else {
                        // If the publish message has QOS2, then we should to wait for the pubrel
                        // The code should actually enqueue the message and process it later when the pubrel is received
                        // Enqueue the message into the QOS2 rx queue
                        try self.qos2Queue.addPublish(packetId, publish_response.qos, publish_response.dup, publish_response.retained, publish_response.topic, publish_response.payload, system.calculateDeadline(2000));
                    }
                },
                .puback => {
                    // Response for Client pub qos1
                    const resp = try mqtt.deserializePuback(&rxBuffer);

                    // Process the puback packet
                    // Acknowledges a QoS1 publish message
                    if (false == try self.qosQueue.acknowledge(resp.packetId, .publish)) {
                        return mqtt_error.qos_packet_not_found;
                    }
                },
                .pingresp => {
                    const ping_timestamp = self.pingQueue.recieve(0).?;

                    _ = c.printf("pingresp! %d, %d\r\n", self.pingCounter, ping_timestamp);
                },
                .connack => try mqtt.processConnAck(&rxBuffer),
                .connect, .subscribe, .disconnect, .unsubscribe, .pingreq => break, // Broker messages
                .suback => {
                    var grantedQoSs: [2]QoS = .{ .qos0, .qos0 };

                    // Deserialize
                    const res = try mqtt.deserializeSubAck(&rxBuffer, &grantedQoSs);
                    _ = res;
                }, // To-do: process the sub-ack
                .unsuback => {
                    // currently unsuported
                },
                .pubrec => {
                    // generate pubrel package
                    // pubrec does not have a duplicate
                    const rx_packetId = try mqtt.deserializePubrec(&rxBuffer);

                    // Remove the publish message from the queue
                    if (false == try self.qosQueue.acknowledge(rx_packetId, .publish)) {
                        return mqtt_error.qos_packet_not_found;
                    }

                    // Search for duplicate packets in queue
                    const dup = try self.qosQueue.acknowledge(rx_packetId, .pubrel);

                    // Prepare the pubrel packet
                    const ret = try self.packet.preparePubRelPacket(rx_packetId, dup);

                    // Add to tx queue
                    try self.qosQueue.addPubRel(ret, false, system.calculateDeadline(2000));
                },
                .pubrel => {
                    // Recieved pubrel from broker
                    const ret = try mqtt.deserializePubrel(&rxBuffer);

                    if (self.qos2Queue.findAndRemove(ret.packetId)) |msg| {

                        // Send the pubcomp packet to the broker
                        _ = try self.packet.preparePubCompPacket(ret.packetId);
                        try self.processSendQueue();

                        var buf: [64]u8 = undefined;
                        @memset(&buf, 0);

                        const s = try std.fmt.bufPrint(&buf, "Pubrel recieved: {d}, {d} {s} {s}\r\n", .{ ret.packetId, @intFromEnum(msg.qos), msg.topic, msg.payload });

                        _ = c.printf("%s", s.ptr);

                        @memset(msg.topic, 0);
                        @memset(msg.payload, 0);

                        self.qos2Queue.message.allocator.free(msg.topic);
                        self.qos2Queue.message.allocator.free(msg.payload);
                    } else {
                        // No message found in the queue
                    }
                },
                .pubcomp => {
                    // publish complete recieved from broker
                    const resp = try mqtt.deserializePubcomp(&rxBuffer);

                    // Look for the pubrel package in the queue
                    if (false == try self.qosQueue.acknowledge(resp, .pubrel)) {
                        return mqtt_error.pubrel_packet_not_found;
                    } else {
                        _ = c.printf("pubcomp received for packetId %d\r\n", resp);
                    }
                },
                .err_msg => break,
            }
        } else {
            _ = c.printf("mqtt: %d\r\n", self.task.getStackHighWaterMark());
        }
        // Check if the task has been suspended
    }
}

fn taskFunction(self: *@This()) noreturn {
    // Clear the buffers
    @memset(&txBuffer, 0);
    @memset(&rxBuffer, 0);
    @memset(&workBuffer, 0);

    self.connectionCounter = 0;
    self.disconnectionCounter = 0;
    self.pingCounter = 0;
    self.pingQueue.create() catch unreachable;

    self.uri_string = legacy.c.config_get_mqtt_url();
    self.device_id = legacy.c.config_get_mqtt_device_id();

    // Get to connect
    while (true) {
        const uri = std.Uri.parse(self.uri_string[0..legacy.c.strlen(self.uri_string)]) catch unreachable;

        self.loop(uri) catch |err| {
            if (err == connection.connection_error.create_error) {
                self.pingQueue.reset();
                self.task.delayTask(1000);
            }
            _ = c.printf("Disconnected... reconnect: %d. %d \r\n", self.connectionCounter, @intFromError(err));
        };
    }

    // Go to disconnect phase
}

fn dummyTaskFunction(self: *@This()) noreturn {
    while (true) {
        self.task.suspendTask();
    }
}

fn pingTimer(self: *@This()) void {
    const curr_tick = self.task.getTickCount();

    self.pingQueue.send(&curr_tick, 0) catch unreachable;
    self.pingCounter += 1;

    _ = self.packet.preparePingPacket() catch unreachable;
}

pub fn publish(self: *@This(), topic: []const u8, payload: []const u8, qos: QoS, dup: bool, packetId: ?u16, deadline: u32) !void {
    const ret = try self.packet.preparePublishPacket(topic, payload, qos, dup, packetId);
    try self.qosQueue.addPublish(ret, qos, dup, false, topic, payload, deadline);
}

fn pubTimer(self: *@This()) void {
    const payload = "test";
    self.publish("zig/pub", payload, .qos2, false, null, system.calculateDeadline(2000)) catch unreachable;
}

pub fn create(self: *@This()) void {
    self.task.create(self, config.rtos_prio_mqtt) catch unreachable;
    self.task.suspendTask();
    if (config.enable_mqtt) {
        self.connection.init();
        self.connection.ssl = @TypeOf(self.connection.ssl).create(self, authCallback, null, null);
        self.pingTimer.create(60000, true, self) catch unreachable;
        self.pubTimer.create(10000, true, self) catch unreachable;
        self.packet.create(&self.connection);
    }
}

/// Connect to the MQTT broker
pub fn connect(self: *@This(), uri: std.Uri) !void {
    self.state = .connecting;
    var packetId: u16 = 0;

    self.connectionCounter += 1;
    errdefer {
        self.state = .err;
        self.connection.close() catch {};
    }

    try self.connection.open(uri, null);

    _ = try self.packet.prepareConnectPacket(self.device_id[0..legacy.c.strlen(self.device_id)], null, null);

    try self.processSendQueue();

    // Wait for the connack
    if (try self.connection.waitRx(5)) {
        if (msgTypes.connack == self.packet.read(&rxBuffer)) {
            try mqtt.processConnAck(&rxBuffer);
        } else {
            return mqtt_error.connect_failed;
        }
    }

    const subTopic = [_]mqtt.MQTTString{
        comptime mqtt.initMQTTString(fw_update_topic),
        comptime mqtt.initMQTTString(conf_update_topic),
    };
    const qos = [_]QoS{ QoS.qos1, QoS.qos2 };
    packetId = try self.packet.prepareSubscribePacket(@constCast(&subTopic), @constCast(&qos));

    try self.processSendQueue();

    // Wait for the connack
    if (try self.connection.waitRx(5)) {
        if (msgTypes.suback == self.packet.read(&rxBuffer)) {
            var grantedQoSs: [2]QoS = .{ .qos0, .qos0 };

            // Deserialize
            const res = try mqtt.deserializeSubAck(&rxBuffer, &grantedQoSs);
            if (res.packetId == packetId) {
                _ = c.printf("Suback received: %d..%d,%d\r\n", res.qos.len, @intFromEnum(res.qos[0]), @intFromEnum(res.qos[1]));
            }
        }
    }

    self.state = .connected;
    self.pingTimer.changePeriod(60000, null) catch unreachable;
    self.pubTimer.start(null) catch unreachable;
}

pub fn disconnect(self: *@This()) !void {
    self.pingTimer.stop(null) catch {};
    self.pubTimer.stop(null) catch {};
    defer {
        self.connection.close() catch {};
        self.disconnectionCounter += 1;
    }

    _ = try self.packet.prepareDisconnectPacket();
    try self.processSendQueue();
}

pub fn resumeTask(self: *@This()) void {
    self.task.resumeTask();
}

pub fn getTaskHandle(self: *@This()) freertos.TaskHandle_t {
    return self.task.getHandle();
}

pub var service: @This() = init();
