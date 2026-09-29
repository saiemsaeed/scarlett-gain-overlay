const std = @import("std");
const builtin = @import("builtin");
const cmod = @import("c.zig");
const glfw = cmod.glfw;
const gl = cmod.gl;
const stb = cmod.stb;

const Color = [4]f32;
const font_data = @embedFile("assets/Inter.ttf");

extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;

pub const Overlay = struct {
    window: *glfw.GLFWwindow,
    label_font: Font,
    value_font: Font,
    theme: Theme,
    visible_until: f64 = 0,
    channel: u8 = 1,
    gain: u8 = 0,
    shown: bool = false,

    const width = 174;
    const height = 88;
    const hold_seconds = 1.9;
    const fade_seconds = 0.55;

    pub fn init() !Overlay {
        if (builtin.os.tag == .linux and cmod.system.getenv("DISPLAY") != null)
            glfw.glfwInitHint(glfw.GLFW_PLATFORM, glfw.GLFW_PLATFORM_X11);
        if (glfw.glfwInit() != glfw.GLFW_TRUE) return error.GlfwInitFailed;
        errdefer glfw.glfwTerminate();

        glfw.glfwWindowHint(glfw.GLFW_VISIBLE, glfw.GLFW_FALSE);
        glfw.glfwWindowHint(glfw.GLFW_DECORATED, glfw.GLFW_FALSE);
        glfw.glfwWindowHint(glfw.GLFW_FLOATING, glfw.GLFW_TRUE);
        glfw.glfwWindowHint(glfw.GLFW_TRANSPARENT_FRAMEBUFFER, glfw.GLFW_TRUE);
        glfw.glfwWindowHint(glfw.GLFW_FOCUS_ON_SHOW, glfw.GLFW_FALSE);
        glfw.glfwWindowHint(glfw.GLFW_MOUSE_PASSTHROUGH, glfw.GLFW_TRUE);
        glfw.glfwWindowHint(glfw.GLFW_SAMPLES, 4);
        if (builtin.os.tag == .macos)
            glfw.glfwWindowHint(glfw.GLFW_COCOA_MENUBAR, glfw.GLFW_FALSE);

        const window = glfw.glfwCreateWindow(width, height, "Scarlett Gain", null, null) orelse
            return error.WindowCreationFailed;
        errdefer glfw.glfwDestroyWindow(window);
        glfw.glfwMakeContextCurrent(window);
        glfw.glfwSwapInterval(1);

        gl.glEnable(gl.GL_BLEND);
        gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);
        gl.glEnable(gl.GL_MULTISAMPLE);
        const label_font = try Font.init(28);
        errdefer label_font.deinit();
        const value_font = try Font.init(68);
        positionAtTopCenter(window);
        return .{
            .window = window,
            .label_font = label_font,
            .value_font = value_font,
            .theme = Theme.load(),
        };
    }

    pub fn deinit(self: *Overlay) void {
        self.label_font.deinit();
        self.value_font.deinit();
        glfw.glfwDestroyWindow(self.window);
        glfw.glfwTerminate();
    }

    pub fn show(self: *Overlay, channel: u8, gain: u8) void {
        self.channel = channel;
        self.gain = gain;
        self.visible_until = glfw.glfwGetTime() + hold_seconds + fade_seconds;
        glfw.glfwSetWindowOpacity(self.window, 1.0);
        if (!self.shown) {
            positionAtTopCenter(self.window);
            glfw.glfwShowWindow(self.window);
            self.shown = true;
        }
        self.draw();
    }

    pub fn tick(self: *Overlay) bool {
        glfw.glfwPollEvents();
        if (glfw.glfwWindowShouldClose(self.window) != 0) return false;
        if (!self.shown) return true;

        const remaining = self.visible_until - glfw.glfwGetTime();
        if (remaining <= 0) {
            glfw.glfwHideWindow(self.window);
            self.shown = false;
            return true;
        }
        glfw.glfwSetWindowOpacity(self.window, if (remaining < fade_seconds)
            @as(f32, @floatCast(remaining / fade_seconds))
        else
            1.0);
        self.draw();
        return true;
    }

    fn draw(self: *Overlay) void {
        var framebuffer_width: c_int = 0;
        var framebuffer_height: c_int = 0;
        glfw.glfwGetFramebufferSize(self.window, &framebuffer_width, &framebuffer_height);
        gl.glViewport(0, 0, framebuffer_width, framebuffer_height);
        gl.glMatrixMode(gl.GL_PROJECTION);
        gl.glLoadIdentity();
        gl.glOrtho(0, width, height, 0, -1, 1);
        gl.glMatrixMode(gl.GL_MODELVIEW);
        gl.glLoadIdentity();
        gl.glClearColor(0, 0, 0, 0);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);

        // A restrained, macOS-style HUD: one surface, one accent, no decoration.
        roundedRect(3, 3, width - 3, height - 3, 21, withAlpha(self.theme.background, 0.96));
        roundedOutline(3.5, 3.5, width - 3.5, height - 3.5, 20.5, withAlpha(self.theme.accent, 0.32));

        circle(53, 44, 20, self.theme.recessed);
        arc(53, 44, 19, -std.math.pi / 2.0,
            -std.math.pi / 2.0 + 2.0 * std.math.pi * @as(f32, @floatFromInt(@min(self.gain, 69))) / 69.0,
            3.0, self.theme.accent);

        var channel_text = [_]u8{'0'};
        channel_text[0] += self.channel;
        const channel_width = self.label_font.measure(&channel_text);
        self.label_font.draw(&channel_text, 53 - channel_width / 2, 49, self.theme.foreground);

        var label = [_]u8{ 'I', 'N', 'P', 'U', 'T', ' ', '0' };
        label[6] += self.channel;
        self.label_font.draw(&label, 88, 30, self.theme.muted);

        var value: [2]u8 = undefined;
        const value_text: []const u8 = if (self.gain >= 10) blk: {
            value[0] = '0' + self.gain / 10;
            value[1] = '0' + self.gain % 10;
            break :blk value[0..2];
        } else blk: {
            value[0] = '0' + self.gain;
            break :blk value[0..1];
        };
        self.value_font.draw(value_text, 87, 68, self.theme.foreground);
        const number_width = self.value_font.measure(value_text);
        self.label_font.draw("dB", 92 + number_width, 65, self.theme.muted);

        glfw.glfwSwapBuffers(self.window);
    }
};

const Theme = struct {
    background: Color = .{ 0.075, 0.078, 0.088, 1 },
    recessed: Color = .{ 0.13, 0.135, 0.15, 1 },
    foreground: Color = .{ 0.97, 0.97, 0.985, 1 },
    muted: Color = .{ 0.62, 0.64, 0.7, 1 },
    accent: Color = .{ 1.0, 0.22, 0.28, 1 },

    fn load() Theme {
        var result = Theme{};
        if (builtin.os.tag != .linux) return result;

        const home_ptr = cmod.system.getenv("HOME") orelse return result;
        const home = std.mem.span(home_ptr);
        var path_buffer: [1024]u8 = undefined;
        const path = std.fmt.bufPrintZ(
            &path_buffer,
            "{s}/.local/state/omarchy/current/theme/colors.toml",
            .{home},
        ) catch return result;
        const file = open(path.ptr, 0); // O_RDONLY
        if (file < 0) return result;
        defer _ = cmod.system.close(file);

        var file_buffer: [4096]u8 = undefined;
        const byte_count = cmod.system.read(file, &file_buffer, file_buffer.len);
        if (byte_count <= 0) return result;
        var lines = std.mem.splitScalar(u8, file_buffer[0..@intCast(byte_count)], '\n');
        while (lines.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");
            const equals = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const key = std.mem.trim(u8, line[0..equals], " \t");
            const raw = std.mem.trim(u8, line[equals + 1 ..], " \t");
            const parsed = parseTomlColor(raw) orelse continue;
            if (std.mem.eql(u8, key, "background")) result.background = parsed;
            if (std.mem.eql(u8, key, "darker_background")) result.recessed = parsed;
            if (std.mem.eql(u8, key, "foreground")) result.foreground = parsed;
            if (std.mem.eql(u8, key, "dark_foreground")) result.muted = parsed;
            if (std.mem.eql(u8, key, "accent")) result.accent = parsed;
        }
        return result;
    }
};

fn parseTomlColor(raw: []const u8) ?Color {
    if (raw.len < 9 or raw[0] != '"' or raw[1] != '#' or raw[8] != '"') return null;
    return .{
        @as(f32, @floatFromInt(hexByte(raw[2], raw[3]) orelse return null)) / 255.0,
        @as(f32, @floatFromInt(hexByte(raw[4], raw[5]) orelse return null)) / 255.0,
        @as(f32, @floatFromInt(hexByte(raw[6], raw[7]) orelse return null)) / 255.0,
        1,
    };
}

fn hexByte(high: u8, low: u8) ?u8 {
    const h = std.fmt.charToDigit(high, 16) catch return null;
    const l = std.fmt.charToDigit(low, 16) catch return null;
    return h * 16 + l;
}

fn withAlpha(value: Color, alpha: f32) Color {
    return .{ value[0], value[1], value[2], alpha };
}

const Font = struct {
    texture: gl.GLuint,
    chars: [96]stb.stbtt_bakedchar,

    fn init(pixel_height: f32) !Font {
        var bitmap: [1024 * 1024]u8 = @splat(0);
        var result: Font = .{ .texture = 0, .chars = undefined };
        if (stb.stbtt_BakeFontBitmap(font_data.ptr, 0, pixel_height, &bitmap, 1024, 1024, 32, 96, &result.chars) <= 0)
            return error.FontRasterizationFailed;
        gl.glGenTextures(1, &result.texture);
        gl.glBindTexture(gl.GL_TEXTURE_2D, result.texture);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
        gl.glPixelStorei(gl.GL_UNPACK_ALIGNMENT, 1);
        gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_ALPHA, 1024, 1024, 0, gl.GL_ALPHA, gl.GL_UNSIGNED_BYTE, &bitmap);
        return result;
    }

    fn deinit(self: Font) void {
        gl.glDeleteTextures(1, &self.texture);
    }

    fn measure(self: *const Font, text: []const u8) f32 {
        var x: f32 = 0;
        var y: f32 = 0;
        var quad: stb.stbtt_aligned_quad = undefined;
        for (text) |char| {
            if (char < 32 or char > 127) continue;
            stb.stbtt_GetBakedQuad(&self.chars, 1024, 1024, char - 32, &x, &y, &quad, 1);
        }
        return x / 2.0;
    }

    fn draw(self: *const Font, text: []const u8, x_start: f32, baseline: f32, value: Color) void {
        var x = x_start * 2.0;
        var y = baseline * 2.0;
        color(value);
        gl.glEnable(gl.GL_TEXTURE_2D);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.texture);
        gl.glBegin(gl.GL_QUADS);
        for (text) |char| {
            if (char < 32 or char > 127) continue;
            var quad: stb.stbtt_aligned_quad = undefined;
            stb.stbtt_GetBakedQuad(&self.chars, 1024, 1024, char - 32, &x, &y, &quad, 1);
            gl.glTexCoord2f(quad.s0, quad.t0); gl.glVertex2f(quad.x0 / 2.0, quad.y0 / 2.0);
            gl.glTexCoord2f(quad.s1, quad.t0); gl.glVertex2f(quad.x1 / 2.0, quad.y0 / 2.0);
            gl.glTexCoord2f(quad.s1, quad.t1); gl.glVertex2f(quad.x1 / 2.0, quad.y1 / 2.0);
            gl.glTexCoord2f(quad.s0, quad.t1); gl.glVertex2f(quad.x0 / 2.0, quad.y1 / 2.0);
        }
        gl.glEnd();
        gl.glDisable(gl.GL_TEXTURE_2D);
    }
};

fn positionAtTopCenter(window: *glfw.GLFWwindow) void {
    const monitor = glfw.glfwGetPrimaryMonitor() orelse return;
    var x: c_int = 0;
    var y: c_int = 0;
    var w: c_int = 0;
    var h: c_int = 0;
    glfw.glfwGetMonitorWorkarea(monitor, &x, &y, &w, &h);
    const overlay_y = if (builtin.os.tag == .macos)
        y + h - Overlay.height - 42
    else
        y + @min(h, 42);
    glfw.glfwSetWindowPos(window, x + @divTrunc(w - Overlay.width, 2), overlay_y);
}

fn color(value: Color) void {
    gl.glColor4f(value[0], value[1], value[2], value[3]);
}

fn roundedRect(x1: f32, y1: f32, x2: f32, y2: f32, radius: f32, value: Color) void {
    color(value);
    gl.glBegin(gl.GL_POLYGON);
    roundedVertices(x1, y1, x2, y2, radius);
    gl.glEnd();
}

fn roundedOutline(x1: f32, y1: f32, x2: f32, y2: f32, radius: f32, value: Color) void {
    color(value);
    gl.glLineWidth(1);
    gl.glBegin(gl.GL_LINE_LOOP);
    roundedVertices(x1, y1, x2, y2, radius);
    gl.glEnd();
}

fn roundedVertices(x1: f32, y1: f32, x2: f32, y2: f32, radius: f32) void {
    const centers = [_][2]f32{
        .{ x1 + radius, y1 + radius }, .{ x2 - radius, y1 + radius },
        .{ x2 - radius, y2 - radius }, .{ x1 + radius, y2 - radius },
    };
    const starts = [_]f32{ std.math.pi, -std.math.pi / 2.0, 0, std.math.pi / 2.0 };
    for (centers, starts) |center, start| {
        var i: u8 = 0;
        while (i <= 12) : (i += 1) {
            const angle = start + @as(f32, @floatFromInt(i)) * (std.math.pi / 2.0) / 12.0;
            gl.glVertex2f(center[0] + @cos(angle) * radius, center[1] + @sin(angle) * radius);
        }
    }
}

fn circle(cx: f32, cy: f32, radius: f32, value: Color) void {
    color(value);
    gl.glBegin(gl.GL_TRIANGLE_FAN);
    gl.glVertex2f(cx, cy);
    var i: u8 = 0;
    while (i <= 48) : (i += 1) {
        const angle = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / 48.0;
        gl.glVertex2f(cx + @cos(angle) * radius, cy + @sin(angle) * radius);
    }
    gl.glEnd();
}

fn arc(cx: f32, cy: f32, radius: f32, start: f32, end: f32, line_width: f32, value: Color) void {
    color(value);
    gl.glLineWidth(line_width);
    gl.glBegin(gl.GL_LINE_STRIP);
    var i: u8 = 0;
    while (i <= 48) : (i += 1) {
        const angle = start + (end - start) * @as(f32, @floatFromInt(i)) / 48.0;
        gl.glVertex2f(cx + @cos(angle) * radius, cy + @sin(angle) * radius);
    }
    gl.glEnd();
}
