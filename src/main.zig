const std = @import("std");
const glfw = @import("c.zig").glfw;
const Scarlett = @import("scarlett.zig").Scarlett;
const Overlay = @import("overlay.zig").Overlay;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var overlay = Overlay.init() catch |err| {
        std.log.err("could not create overlay: {s}", .{@errorName(err)});
        return err;
    };
    defer overlay.deinit();

    if (args.len > 1 and std.mem.eql(u8, args[1], "--demo")) {
        overlay.show(1, 47);
        while (overlay.tick() and glfw.glfwGetTime() < 8)
            glfw.glfwWaitEventsTimeout(0.012);
        return;
    }

    var scarlett = Scarlett.open() catch |err| {
        std.log.err("could not open Scarlett 2i2 4th Gen: {s}", .{@errorName(err)});
        return err;
    };
    defer scarlett.close();

    var previous = try scarlett.readGains();
    std.log.info("Scarlett connected; input gains are {d} dB and {d} dB", .{ previous[0], previous[1] });

    var next_poll = glfw.glfwGetTime();
    while (overlay.tick()) {
        const now = glfw.glfwGetTime();
        if (now >= next_poll) {
            const current = scarlett.readGains() catch |err| {
                std.log.err("lost communication with Scarlett: {s}", .{@errorName(err)});
                return err;
            };
            for (current, 0..) |gain, index| {
                if (gain != previous[index]) {
                    std.log.info("input {d} gain changed: {d} dB -> {d} dB", .{ index + 1, previous[index], gain });
                    overlay.show(@intCast(index + 1), gain);
                }
            }
            previous = current;
            next_poll = now + 0.075;
        }
        glfw.glfwWaitEventsTimeout(0.012);
    }
}
