const builtin = @import("builtin");

pub const usb = @cImport({
    @cInclude("libusb.h");
});

pub const system = @cImport({
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
});

pub const glfw = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cInclude("GLFW/glfw3.h");
});

pub const stb = @cImport({
    @cInclude("stb_truetype.h");
});

pub const gl = if (builtin.os.tag == .macos) @cImport({
    @cInclude("OpenGL/gl.h");
}) else @cImport({
    @cInclude("GL/gl.h");
});
