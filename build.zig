const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "scarlett-gain-overlay",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.link_libc = true;
    exe.root_module.addIncludePath(b.path("vendor"));
    exe.root_module.addCSourceFile(.{
        .file = b.path("vendor/stb_truetype_impl.c"),
        .flags = &.{"-O2"},
    });

    exe.root_module.addIncludePath(b.path("vendor/glfw/include"));
    exe.root_module.addIncludePath(b.path("vendor/glfw/src"));
    const glfw_platform_define = if (target.result.os.tag == .macos) "-D_GLFW_COCOA" else "-D_GLFW_X11";
    const glfw_common_sources = [_][]const u8{
        "context.c", "egl_context.c", "init.c", "input.c", "monitor.c",
        "null_init.c", "null_joystick.c", "null_monitor.c", "null_window.c",
        "osmesa_context.c", "platform.c", "posix_module.c", "posix_thread.c",
        "vulkan.c", "window.c",
    };
    for (glfw_common_sources) |source| {
        exe.root_module.addCSourceFile(.{
            .file = b.path(b.fmt("vendor/glfw/src/{s}", .{source})),
            .flags = &.{ "-O2", glfw_platform_define },
        });
    }

    const local_libusb = b.option(bool, "local-libusb", "Use the locally extracted macOS libusb archive") orelse false;
    if (local_libusb and target.result.os.tag == .macos) {
        exe.root_module.addIncludePath(b.path(".deps/libusb/1.0.30/include/libusb-1.0"));
        exe.root_module.addObjectFile(b.path(".deps/libusb/1.0.30/lib/libusb-1.0.a"));
    } else {
        exe.root_module.linkSystemLibrary("usb-1.0", .{});
    }

    if (target.result.os.tag == .macos) {
        const cocoa_sources = [_][]const u8{
            "cocoa_init.m", "cocoa_joystick.m", "cocoa_monitor.m",
            "cocoa_window.m", "macos_time.c", "nsgl_context.m",
        };
        for (cocoa_sources) |source| {
            exe.root_module.addCSourceFile(.{
                .file = b.path(b.fmt("vendor/glfw/src/{s}", .{source})),
                .flags = &.{ "-O2", "-D_GLFW_COCOA" },
            });
        }
        exe.root_module.linkFramework("Cocoa", .{});
        exe.root_module.linkFramework("IOKit", .{});
        exe.root_module.linkFramework("CoreFoundation", .{});
        exe.root_module.linkFramework("Security", .{});
        exe.root_module.linkFramework("OpenGL", .{});
        exe.root_module.linkFramework("QuartzCore", .{});
    } else {
        const x11_sources = [_][]const u8{
            "glx_context.c", "linux_joystick.c", "posix_poll.c", "posix_time.c",
            "x11_init.c", "x11_monitor.c", "x11_window.c", "xkb_unicode.c",
        };
        for (x11_sources) |source| {
            exe.root_module.addCSourceFile(.{
                .file = b.path(b.fmt("vendor/glfw/src/{s}", .{source})),
                .flags = &.{ "-O2", "-D_GLFW_X11" },
            });
        }
        exe.root_module.linkSystemLibrary("GL", .{});
        exe.root_module.linkSystemLibrary("X11", .{});
        exe.root_module.linkSystemLibrary("Xrandr", .{});
        exe.root_module.linkSystemLibrary("Xi", .{});
        exe.root_module.linkSystemLibrary("Xcursor", .{});
        exe.root_module.linkSystemLibrary("Xinerama", .{});
        exe.root_module.linkSystemLibrary("dl", .{});
        exe.root_module.linkSystemLibrary("m", .{});
        exe.root_module.linkSystemLibrary("pthread", .{});
    }

    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the overlay").dependOn(&run.step);
}
