const std = @import("std");
const phr = @import("picohttpparser");

pub const phr_header = phr.phr_header;
pub const phr_response = phr.response;

pub const header_error = error{
    phr_library_parse_failed,
    parse_error,
    range_response_parse_error,

    rx_timeout,
    rx_error,
};

/// HTTP Response Header Types
pub const responseHeaders = enum(usize) {
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
    pub fn match(header: phr_header) ?@This() {
        return stringMap.get(header.name[0..(header.name_len)]);
    }
};

/// Accept-Ranges Header
pub const acceptRanges = enum(usize) {
    none = @intFromBool(false),
    bytes = @intFromBool(true),

    const stringMap = std.StaticStringMap(@This()).initComptime(.{ .{ "bytes", .bytes }, .{ "none", .none } });

    pub fn match(header: phr_header) !@This() {
        return (stringMap.get(header.value[0..(header.value_len)])) orelse header_error.parse_error;
    }
};

/// Keep-Alive Header
pub const keepAlive = enum(usize) {
    keep_alive = @intFromBool(true),
    close = @intFromBool(false),

    const stringMap = std.StaticStringMap(@This()).initComptime(.{ .{ "keep-alive", .keep_alive }, .{ "close", .close } });

    pub fn match(header: phr.phr_header) !@This() {
        return (stringMap.get(header.value[0..(header.value_len)])) orelse header_error.parse_error;
    }
};

/// Content Type Header
pub const contentType = enum(usize) {
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
    pub fn match(header: phr_header) !@This() {
        for (strings, 0..) |ct, idx| {
            if (header.value_len >= ct.len) {
                if (std.mem.eql(u8, header.value[0..ct.len], ct)) {
                    return @enumFromInt(idx);
                }
            }
        }

        return header_error.parse_error;
    }

    /// Get the string representation of the content type
    pub fn getString(id: @This()) []const u8 {
        return strings[@intFromEnum(id)];
    }
};

/// Structure representing a parsed Content-Range response header.
pub const rangeResponse = struct {
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
    pub fn match(header: phr_header) !?@This() {
        // Pre-fill the returned structure with default values
        var ret: @This() = .{ .start = 0, .end = 0, .total = null };

        // Check if the header contains the expected "bytes " string
        if (!std.mem.eql(u8, header.value[0.."bytes ".len], "bytes ")) {
            return header_error.range_response_parse_error; // Does not contain the expected "bytes " string
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

pub const response = struct {
    payload: ?[]u8,
    headers: []phr_header,
    status: u32,

    const response_parse = phr_response.parse;

    pub const rx_callback_error = error{
        rx_timeout,
        rx_error,
    };

    pub const wait_for_rx_callback_fn = *const fn (opaque_conn: *anyopaque, buffer: []u8, timeout: u32) rx_callback_error![]u8;

    /// HTTP Response from server
    /// Receive an HTTP response from the server and parse headers.
    pub fn recieveResponse(connection: *anyopaque, rx_buffer: []u8, headers: []phr_header, comptime wait_for_rx_callback: wait_for_rx_callback_fn) !@This() {
        var rx_count: usize = 0;
        var pret: i32 = -2; // Incomplete request
        var prevbuflen: usize = 0;

        var status: i32 = undefined;
        var payload_len: usize = undefined;
        var payload: ?[]u8 = null;
        var parsed_headers: []phr_header = undefined;
        var timeouts: usize = 4;

        while ((pret == -2) and (rx_count < rx_buffer.len)) {
            // Use the callback to wait for and receive data
            const rec = wait_for_rx_callback(connection, rx_buffer[rx_count..], 2) catch |err| {
                switch (err) {
                    rx_callback_error.rx_timeout => {
                        if (timeouts == 0) {
                            return header_error.rx_timeout;
                        } else {
                            timeouts -= 1;
                            continue;
                        }
                    },
                    rx_callback_error.rx_error => return header_error.rx_error,
                }
            };

            const res = try response_parse(rec, prevbuflen, headers);

            pret = res.result;
            status = res.status;
            parsed_headers = res.headers;
            prevbuflen = rx_count;
            rx_count += rec.len;
        }

        if (pret >= 0) {
            payload_len = rx_count - @as(usize, @intCast(pret));
            payload = if (payload_len != 0) rx_buffer[(rx_count - payload_len)..rx_count] else null;
        }

        return if (pret >= 0) .{ .payload = payload, .headers = parsed_headers, .status = @intCast(status) } else header_error.phr_library_parse_failed;
    }
};

/// Structure representing a parsed HTTP response.
pub const parsedResponse = struct {
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
    pub fn processHeaders(self: *@This(), rx: response) !u32 {

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
