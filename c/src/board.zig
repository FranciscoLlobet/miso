const std = @import("std");
const c = @cImport({
    @cInclude("board.h");
    //@cInclude("miso.h");
    //@cInclude("miso_config.h");
});

pub export fn init() void {
    c.BOARD_Init();
}
