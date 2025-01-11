const std = @import("std");
pub const c = @cImport({
    @cInclude("picohttpparser.h");
});

pub const phr_header = c.phr_header;
pub const phr_parse_response = c.phr_parse_response;
