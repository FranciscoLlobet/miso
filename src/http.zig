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

const std = @import("std");
const freertos = @import("freertos");
const config = @import("config.zig");
const system = @import("board");
const legacy = @import("legacy");
//const connection = legacy.connection;
const simpleConnection = legacy.simpleConnection;
const file = @import("fatfs").file;

const http_header = @import("http/header.zig");

const responseHeaders = http_header.responseHeaders;
const acceptRanges = http_header.acceptRanges;
const contentType = http_header.contentType;
const keepAlive = http_header.keepAlive;
const rangeResponse = http_header.rangeResponse;
const phr_header = http_header.phr_header;

const connectionType = legacy.connection.Connection(simpleConnection.SimpleLinkConnection(.tcp_ip4));

/// Connection instance
connection: connectionType,

/// Array to store parsed header information
/// Assumption that most server responses will return less than 24 headers
headers: [24]phr_header,

/// TX Buffer
tx_buffer: [256]u8 align(@alignOf(u32)),

/// RX Buffer
rx_buffer: [1536]u8 align(@alignOf(u32)),

// Etag buffer
etag: [64]u8,

etag_slice: ?[]u8,

file: file,

const @"error" = error{
    rx_error,
    tx_error,

    /// PHR parse failed
    phr_library_parse_failed,

    parse_error,

    timeout,
    connection_error,

    /// Status Code Not OK (200)
    status_code_nok,

    file_size_not_found,

    /// Downloaded file size does not match the expected size
    file_size_mismatch,

    /// Advertized file size exceeds the maximum allowed size
    file_size_exceeded,

    /// Unexpected Status Code
    unexpected_status_code,

    range_response_parse_error,
};

// Example callback implementation for a specific connection type
fn connectionWaitForRxCallback(opaque_conn: *anyopaque, buffer: []u8, timeout: u32) http_header.response.rx_callback_error![]u8 {
    // Cast the opaque connection back to the concrete type
    const connection = @as(*connectionType, @ptrCast(@alignCast(opaque_conn)));
    var received_data: []u8 = undefined;

    const rx_av = connection.waitRx(timeout) catch {
        return http_header.response.rx_callback_error.rx_error;
    };

    if (rx_av) {
        received_data = connection.recieve(buffer) catch {
            return http_header.response.rx_callback_error.rx_error;
        };
    } else {
        return http_header.response.rx_callback_error.rx_timeout;
    }

    return received_data;
}

/// Authentication callback function.
/// Used during the connection phase for providing PSK credentials
fn authCallback(self: *legacy.connection.mbedtls, security_mode: legacy.connection.security_mode) legacy.connection.mbedtls.auth_error!void {
    _ = self;
    if (security_mode == .psk) {
        // PSK authentication
    } else if (security_mode == .certificate_ec) {
        // EC Certificate
    } else {
        // Unsuported security mode
    }
}

/// Function to send an HTTP GET request with a specific byte range.
/// The range is specified by the 'start' and 'end' parameters.
pub fn sendGetRangeRequest(tx_buffer: []u8, uri: *const std.Uri, start: usize, end: usize) ![]u8 {
    return std.fmt.bufPrint(tx_buffer, "GET {s} HTTP/1.1\r\nHost: {s}\r\nRange: bytes={d}-{d}\r\n\r\n", .{ uri.path.percent_encoded, uri.host.?.percent_encoded, start, end });
}

/// Function to send an HTTP HEAD request to a specified URL.
/// HEAD requests retrieve the headers without the message body.
pub fn sendHeadRequest(tx_buffer: []u8, uri: *const std.Uri) ![]u8 {
    return std.fmt.bufPrint(tx_buffer, "HEAD {s} HTTP/1.1\r\nHost: {s}\r\n\r\n", .{ uri.path.percent_encoded, uri.host.?.percent_encoded });
}

/// Calculate the end position of the range request
///
/// This function will try to synchronise the request end position with the block-size.
inline fn calcRequestEnd(file_size: usize, comptime block_size: usize, current_position: usize) usize {
    const remainder = current_position % block_size;
    const block_request_size = if (remainder == 0) block_size else (block_size - remainder);
    const requestEnd = current_position + block_request_size - 1;
    return if (requestEnd > (file_size - 1)) (file_size - 1) else requestEnd;
}

/// File Download using HTTP
///
/// This function will download a file from a specified URI and store it in the file system
///
pub fn filedownload(self: *@This(), uri: std.Uri, file_name: [*:0]const u8, comptime block_size: usize, comptime max_file_size: usize) !?[]u8 {
    var parsed_response: http_header.parsedResponse = undefined;

    //@memset(&self.tx_buffer, 0);
    //@memset(&self.rx_buffer, 0);

    try self.connection.open(uri, null);
    defer {
        self.connection.close() catch {};
        @memset(&self.tx_buffer, 0);
        @memset(&self.rx_buffer, 0);
    }

    _ = try self.connection.send(try sendHeadRequest(&self.tx_buffer, &uri));

    if (200 != try parsed_response.processHeaders(try http_header.response.recieveResponse(&self.connection, &self.rx_buffer, &self.headers, connectionWaitForRxCallback))) {
        return @"error".status_code_nok;
    }

    if (parsed_response.content_length == null) {
        return @"error".file_size_not_found;
    }

    const fileSize: usize = parsed_response.content_length.?;
    if (fileSize > max_file_size) {
        return @"error".file_size_exceeded;
    }

    if (parsed_response.getEtag()) |etag| {
        if (etag.len > self.etag.len) {
            @memcpy(self.etag[0..].ptr, etag[0..self.etag.len]);
            self.etag_slice = self.etag[0..self.etag.len];
        } else {
            @memcpy(self.etag[0..].ptr, etag);
            self.etag_slice = self.etag[0..etag.len];
        }
    } else {
        self.etag_slice = null;
    }

    // Open the file for writing
    self.file = try file.open(file_name, @intFromEnum(file.fMode.create_always) | @intFromEnum(file.fMode.write));
    defer {
        self.file.close() catch {};
    }

    try self.file.sync(); // Perfom sync to reduce chances of critical errors

    while (self.file.tell() < fileSize) {
        // Calculate the end position of the request
        const startPosition: usize = self.file.tell();

        const requestEnd = calcRequestEnd(fileSize, block_size, startPosition);

        _ = try self.connection.send(try sendGetRangeRequest(&self.tx_buffer, &uri, startPosition, requestEnd));

        // We expect a HTTP code 206 Partial Content.
        if (206 == try parsed_response.processHeaders(try http_header.response.recieveResponse(&self.connection, &self.rx_buffer, &self.headers, connectionWaitForRxCallback))) {

            // Check if the response contains the expected range header
            if (parsed_response.range == null) {
                return @"error".range_response_parse_error;
            }

            // We compare the start position of the response with starting file pointer position
            // If they do not match, we need to rewind the file a previous position
            // If the start position is smaller than the current position, we need to rewind to the start of the file in order to avoid holes and file corruption.
            if (startPosition != parsed_response.range.?.start) {
                if (startPosition > parsed_response.range.?.start) {
                    // Rewind to the range response start position
                    try self.file.lseek(parsed_response.range.?.start);
                } else {
                    // The starting position is outside the written range
                    // Rewind to file start
                    try self.file.rewind();
                    try self.file.sync();
                    continue; // Restart the download
                }
            }

            const written_bytes = try self.file.write(parsed_response.payload.?);

            // Perform sync to reduce chances of critical errors
            try self.file.sync();

            if (requestEnd != parsed_response.range.?.end) {
                // Request end position does not match with the expected value
                // Not so tragic...
            }

            if (written_bytes != parsed_response.payload.?.len) {
                // The write operation did not write the full block.
                // This used to an error, but it is not critical
                // In the future I will add a warning message
            }
        } else {
            return @"error".unexpected_status_code;
        }

        // Check if the server wants to keep the connection alive
        if (parsed_response.keep_alive) |kA| {
            if (kA == .close) {
                // Think about closing the file and reopening it
                self.file.sync() catch {};

                // Reconnect logic
                try self.connection.close();

                try self.connection.open(uri, null);
            } else {
                //  Keep Alive
            }
        }
    }

    if (self.file.tell() != fileSize) {
        return @"error".file_size_mismatch;
    }

    // File and connection closure are deferred at the start

    // return the etag
    return self.etag_slice;
}

pub fn eTag(self: *@This()) ?[]const u8 {
    return self.etag;
}

pub fn create(self: *@This()) void {
    if (config.enable_http) {
        self.connection.init();
    }
}

pub var service: @This() = undefined;
