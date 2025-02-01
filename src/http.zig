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
const phr = @import("picohttpparser");

const connectionType = legacy.connection.Connection(simpleConnection.SimpleLinkConnection(.tcp_ip4));

/// Connection instance
connection: connectionType,

/// Array to store parsed header information
/// Assumption that most server responses will return less than 24 headers
headers: [24]phr.phr_header,

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

/// HTTP Response from server
const rx_response = struct {
    payload: ?[]u8,
    headers: []phr.phr_header,
    status: u32,

    /// Recieve an HTTP response from the server.
    fn recieveResponse(connection: *connectionType, rx_buffer: []u8, headers: []phr.phr_header) !rx_response {
        var rx_count: usize = 0;
        var pret: i32 = -2; // Incomplete request
        var prevbuflen: usize = 0;

        var status: i32 = undefined;
        var payload_len: usize = undefined;
        var payload: ?[]u8 = null;
        var parsed_headers: []phr.phr_header = undefined;
        var timeouts: usize = 4;

        while ((pret == -2) and (rx_count < rx_buffer.len)) {
            if (try connection.waitRx(2)) {
                const rec = try connection.recieve(rx_buffer[rx_count..]);

                const res = try phr.response.parse(rec, prevbuflen, headers);

                pret = res.result;
                status = res.status;
                parsed_headers = res.headers;
                prevbuflen = rx_count;
                rx_count += rec.len;
            } else {
                if (timeouts == 0) {
                    return @"error".timeout;
                } else {
                    timeouts -= 1;
                }

                // rx Timeout
            }
        }

        if (pret >= 0) {
            payload_len = rx_count - @as(usize, @intCast(pret));
            payload = if (payload_len != 0) rx_buffer[(rx_count - payload_len)..rx_count] else null;
        }

        return if (pret >= 0) .{ .payload = payload, .headers = parsed_headers, .status = @intCast(status) } else @"error".phr_library_parse_failed;
    }
};

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

/// Structure representing a parsed Content-Range response header.
const rangeResponse = struct {
    /// Start position of the range
    start: usize,

    /// End position of the range
    end: usize,

    /// Optional total size
    total: ?usize,

    /// Function to parse the Content-Range header
    ///
    /// - 206 partial-content: This function is currently parsing correctly a 206 response. Format: {start}-{end}/{total}
    /// - 416 Requested Range Not Satisfiable. Here the format is */{total} where {total} is the total size.
    ///
    /// This function will parse and assume the happy path (206 - Partial Content).
    fn match(header: phr.phr_header) !?@This() {
        // Pre-fill the returned structure with default values
        var ret: @This() = .{ .start = 0, .end = 0, .total = null };

        // Check if the header contains the expected "bytes " string
        if (!std.mem.eql(u8, header.value[0.."bytes ".len], "bytes ")) {
            return @"error".range_response_parse_error; // Does not contain the expected "bytes " string
        } else if (std.mem.eql(u8, header.value[0.."bytes *".len], "bytes *")) {
            // Requested Range Not Satisfiable
            return null;
        } else {
            var iter = std.mem.splitAny(u8, header.value["bytes ".len..header.value_len], "-/");

            // Get the start position
            ret.start = try std.fmt.parseInt(usize, iter.first(), 10);
            if (iter.next()) |val| {
                ret.end = try std.fmt.parseInt(usize, val, 10);
            }
            if (iter.next()) |val| {
                ret.total = try std.fmt.parseInt(usize, val, 10);
            }
        }

        return ret;
    }
};

/// Structure representing a parsed HTTP response.
const parsedResponse = struct {
    /// Response status code
    status_code: u32,

    /// Content-type
    content_type: ?contentType,

    /// Content-length
    content_length: ?usize,

    /// Optional Content-Range
    range: ?rangeResponse,

    /// Optional Accept-Ranges
    accept_ranges: ?acceptRanges,

    /// Optional Keep-Alive response
    keep_alive: ?keepAlive,

    /// Optional Payload slice
    payload: ?[]const u8,

    /// Optional etag
    etag: ?[]const u8,

    /// Function to process the HTTP response headers.
    /// The function will parse the headers from rx response and store the values in the structure.
    /// The function will return the HTTP status code.
    fn processHeaders(self: *@This(), rx: rx_response) !u32 {

        // Set default values
        self.* = .{ .payload = rx.payload, .status_code = rx.status, .content_type = null, .content_length = null, .range = null, .accept_ranges = null, .etag = null, .keep_alive = null };

        // Process specific headers based on their type.
        for (rx.headers) |header| {
            if (responseHeaders.match(header)) |val| {
                switch (val) {
                    .contentRange => {
                        // Parse and store the Content-Range header details.
                        self.range = try rangeResponse.match(header);
                    },
                    .acceptRanges => {
                        // Parse and store the Accept-Ranges header value.
                        self.accept_ranges = try acceptRanges.match(header);
                    },
                    .contentLength => {
                        // Parse and store the Content-Length header value.
                        self.content_length = try std.fmt.parseInt(usize, header.value[0..header.value_len], 10);
                    },
                    .etag => {
                        // Convert ETag information into slice
                        self.etag = header.value[0..header.value_len];
                    },
                    .connection => {
                        // Determine if the connection should be kept alive or closed.
                        self.keep_alive = try keepAlive.match(header);
                    },
                    else => {
                        // ... other headers can be added and processed as needed ...
                    },
                }
            }
        }
        return self.status_code;
    }

    pub fn getEtag(self: *@This()) ?[]const u8 {
        return self.etag;
    }
};

/// Function to send an HTTP GET request to a specified URL.
pub fn sendGetRequest(self: *@This(), uri: *std.Uri) !void {
    const request = try std.fmt.bufPrint(&self.tx_buffer, "GET {s} HTTP/1.1\r\nHost: {s}\r\n\r\n", .{ uri.path, uri.host.? });
    try self.connection.send(@ptrCast(request), request.len);
}

/// Function to send an HTTP GET request with a specific byte range.
/// The range is specified by the 'start' and 'end' parameters.
pub fn sendGetRangeRequest(self: *@This(), uri: *const std.Uri, start: usize, end: usize) !void {
    const request = try std.fmt.bufPrint(&self.tx_buffer, "GET {s} HTTP/1.1\r\nHost: {s}\r\nRange: bytes={d}-{d}\r\n\r\n", .{ uri.path.percent_encoded, uri.host.?.percent_encoded, start, end });
    _ = try self.connection.send(request);
}

/// Function to send an HTTP HEAD request to a specified URL.
/// HEAD requests retrieve the headers without the message body.
pub fn sendHeadRequest(self: *@This(), uri: *const std.Uri) !void {
    const request = try std.fmt.bufPrint(&self.tx_buffer, "HEAD {s} HTTP/1.1\r\nHost: {s}\r\n\r\n", .{ uri.path.percent_encoded, uri.host.?.percent_encoded });
    _ = try self.connection.send(request);
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
    var parsed_response: parsedResponse = undefined;

    // Parse the URI
    //const uri = try std.Uri.parse(url);

    try self.connection.open(uri, null);
    defer {
        self.connection.close() catch {};
    }

    try self.sendHeadRequest(&uri);

    if (200 != try parsed_response.processHeaders(try rx_response.recieveResponse(&self.connection, &self.rx_buffer, &self.headers))) {
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
        const requestEnd = calcRequestEnd(fileSize, block_size, self.file.tell());

        try self.sendGetRangeRequest(&uri, self.file.tell(), requestEnd);

        // We expect a HTTP code 206 Partial Content.
        if (206 == try parsed_response.processHeaders(try rx_response.recieveResponse(&self.connection, &self.rx_buffer, &self.headers))) {

            // Check if the response contains the expected range header
            if (parsed_response.range == null) {
                return @"error".range_response_parse_error;
            }

            // We compare the start position of the response with current file pointer position
            // If they do not match, we need to rewind the file a previous position
            // If the start position is smaller than the current position, we need to rewind to the start of the file in order to avoid holes and file corruption.
            if (self.file.tell() != parsed_response.range.?.start) {
                if (self.file.tell() > parsed_response.range.?.start) {
                    // Rewind to a previous position.
                    try self.file.lseek(parsed_response.range.?.start);
                } else {
                    // Rewind to file start
                    // This code will effectively rewind the file and restart the transfer.
                    try self.file.rewind();
                    try self.file.sync();
                    continue;
                }
            }

            if (requestEnd != parsed_response.range.?.end) {
                // Request end position does not match with the expected value
                // Not so tragic...
            }

            // Write the payload to the file
            // We store the current file position.
            // If the amount of bytes written into the file does not match with the expected length, we rewind to the previous position.
            const current_position = self.file.tell();
            if (parsed_response.payload.?.len != try self.file.write(parsed_response.payload.?)) {
                // Test if the bytes written match the payload.
                // current error handling will rewind to previous position
                try self.file.lseek(current_position);
            }

            // Move current position to the current file pointer
            // This is probably not necessary since the current position can be calculated from the block size.
            // However three things can happen:
            //   1. The response length is smaller than the requested block size.
            //   2. The write function could not write the full block.
            //   3. The response start position is not equal to requested start position.
            //
            // Here the code avoids throwing a failure cases and performs a re-synchronisation of the current pointers.
            //
            // A case that is not taken into account is when the current position is no longer aligned with the block size.
            // In this case, due to block misalignement the write operation might take longer than expected.

            // Perform sync to reduce chances of critical errors
            try self.file.sync();
        } else {
            return @"error".unexpected_status_code;
        }
        if (parsed_response.keep_alive) |kA| {
            if (kA == .close) {
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

    // return the etag ?
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

/// HTTP Response Header Types
const responseHeaders = enum(usize) {
    contentType,
    contentLength,
    contentRange,
    connection,
    contentLocation,
    contentEncoding,
    acceptRanges,
    etag,

    const stringMap = std.StaticStringMap(@This()).initComptime(.{ .{ "Content-Type", .contentType }, .{ "Content-Length", .contentLength }, .{ "Content-Range", .contentRange }, .{ "Connection", .connection }, .{ "Content-Location", .contentLocation }, .{ "Content-Encoding", .contentEncoding }, .{ "Accept-Ranges", .acceptRanges }, .{ "ETag", .etag } });

    /// Match a response header to the stringmap
    fn match(header: phr.phr_header) ?@This() {
        return stringMap.get(header.name[0..(header.name_len)]);
    }
};

/// Parse the accept ranges header
const acceptRanges = enum(usize) {
    none = @intFromBool(false),
    bytes = @intFromBool(true),

    const stringMap = std.StaticStringMap(@This()).initComptime(.{ .{ "bytes", .bytes }, .{ "none", .none } });

    fn match(header: phr.phr_header) !@This() {
        return (stringMap.get(header.value[0..(header.value_len)])) orelse @"error".parse_error;
    }
};

const keepAlive = enum(usize) {
    keep_alive = @intFromBool(true),
    close = @intFromBool(false),

    const stringMap = std.StaticStringMap(@This()).initComptime(.{ .{ "keep-alive", .keep_alive }, .{ "close", .close } });

    fn match(header: phr.phr_header) !@This() {
        return (stringMap.get(header.value[0..(header.value_len)])) orelse @"error".parse_error;
    }
};

const contentType = enum(usize) {
    unknown = 0,
    text_html,
    text_plain,
    application_json,
    application_xml,
    application_javascript,
    text_css,
    image_jpeg,
    application_octet_stream,
    application_pdf,
    application_zip,
    multipart_byteranges,

    const strings = [_][]const u8{ "Unknown", "text/html", "text/plain", "application/json", "application/xml", "application/javascript", "text/css", "image/jpeg", "application/octet-stream", "application/pdf", "application/zip", "multipart/byteranges" };

    /// Match content to Content-Type(s)
    fn match(header: phr.phr_header) !@This() {
        for (strings, 0..) |ct, idx| {
            if (header.value_len >= ct.len) {
                if (std.mem.eql(u8, header.value[0..ct.len], ct)) {
                    return @enumFromInt(idx);
                }
            }
        }

        return @"error".parse_error;
    }

    fn getString(id: @This()) []const u8 {
        return strings[@intFromEnum(id)];
    }
};

pub var service: @This() = undefined;
