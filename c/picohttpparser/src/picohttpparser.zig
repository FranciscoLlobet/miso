const std = @import("std");
pub const c = @cImport({
    @cInclude("picohttpparser.h");
});

/// PHR Header type
pub const phr_header = c.phr_header;

/// Phr response parser
const phr_parse_response = c.phr_parse_response;

pub fn parse_response(buffer: []u8, last_len: usize, headers: []phr_header) struct {
    result: i32,
    minor_version: i32,
    status: i32,
    msg: []u8,
    headers: []phr_header,
    last_len: usize,
} {
    var minor_version: c_int = 0;
    var status: c_int = 0;
    var msg: [*c]u8 = undefined;
    var msg_len: usize = 0;
    var num_headers: usize = headers.len;

    const result = phr_parse_response(@ptrCast(buffer.ptr), buffer.len, @ptrCast(&minor_version), @ptrCast(&status), &msg, &msg_len, headers.ptr, &num_headers, last_len);

    return .{
        .result = @intCast(result),
        .minor_version = @intCast(minor_version),
        .status = @intCast(status),
        .msg = msg[0..msg_len],
        .headers = headers[0..num_headers],
        .last_len = last_len,
    };
}

// returns number of bytes consumed if successful, -2 if request is partial,
// * -1 if failed */
//int phr_parse_request(const char *buf, size_t len, const char **method, size_t *method_len, const char **path, size_t *path_len,
//                      int *minor_version, struct phr_header *headers, size_t *num_headers, size_t last_len);

////int phr_parse_response(const char *_buf, size_t len, int *minor_version, int *status, const char **msg, size_t *msg_len,
//                       struct phr_header *headers, size_t *num_headers, size_t last_len);

// ditto */
//int phr_parse_headers(const char *buf, size_t len, struct phr_header *headers, size_t *num_headers, size_t last_len);
