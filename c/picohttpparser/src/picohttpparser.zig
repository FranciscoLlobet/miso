const std = @import("std");
pub const c = @cImport({
    @cInclude("picohttpparser.h");
});
