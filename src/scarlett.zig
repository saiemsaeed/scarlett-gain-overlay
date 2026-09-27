const cmod = @import("c.zig");
const c = cmod.usb;
const system = cmod.system;

pub const Gains = [2]u8;

pub const Scarlett = struct {
    context: ?*c.libusb_context,
    handle: *c.libusb_device_handle,
    sequence: u16,

    const vendor_id: u16 = 0x1235;
    const product_id: u16 = 0x8219;
    const control_interface: u16 = 3;
    const notification_endpoint: u8 = 0x83;
    const input_gain_offset: u32 = 0x4b;

    pub fn open() !Scarlett {
        var context: ?*c.libusb_context = null;
        if (c.libusb_init(&context) != 0) return error.UsbInitFailed;
        errdefer c.libusb_exit(context);

        var handle = c.libusb_open_device_with_vid_pid(context, vendor_id, product_id) orelse
            return error.DeviceNotFound;
        errdefer c.libusb_close(handle);

        try claim(handle);
        var self = Scarlett{ .context = context, .handle = handle, .sequence = 0 };
        self.initialize() catch {
            // A client terminated without releasing FCP can leave firmware waiting
            // for its old sequence. Recover once by resetting only this USB device.
            _ = c.libusb_reset_device(handle);
            _ = c.libusb_release_interface(handle, control_interface);
            _ = system.usleep(750_000);

            const reopened = c.libusb_open_device_with_vid_pid(context, vendor_id, product_id) orelse
                return error.DeviceNotFound;
            c.libusb_close(handle);
            handle = reopened;
            self.handle = reopened;
            try claim(handle);
            try self.initialize();
        };
        return self;
    }

    pub fn close(self: *Scarlett) void {
        _ = c.libusb_release_interface(self.handle, control_interface);
        c.libusb_close(self.handle);
        c.libusb_exit(self.context);
    }

    pub fn readGains(self: *Scarlett) !Gains {
        var query: [8]u8 = undefined;
        putU32(query[0..4], input_gain_offset);
        putU32(query[4..8], 2);
        var result: Gains = undefined;
        try self.command(0x00800000, &query, &result);
        return result;
    }

    fn claim(handle: *c.libusb_device_handle) !void {
        // On Linux only the vendor-specific interface is detached. Audio streaming
        // interfaces remain owned by ALSA. This call is unsupported elsewhere.
        _ = c.libusb_set_auto_detach_kernel_driver(handle, 1);
        if (c.libusb_claim_interface(handle, control_interface) != 0)
            return error.InterfaceBusy;
    }

    fn initialize(self: *Scarlett) !void {
        var step_zero: [24]u8 = undefined;
        const init_result = c.libusb_control_transfer(
            self.handle,
            0xa1,
            0,
            0,
            control_interface,
            &step_zero,
            step_zero.len,
            1000,
        );
        if (init_result != step_zero.len) return error.ProtocolInitFailed;

        // Discard any notification queued by an earlier client/session.
        var stale: [8]u8 = undefined;
        var transferred: c_int = 0;
        while (c.libusb_interrupt_transfer(
            self.handle,
            notification_endpoint,
            &stale,
            stale.len,
            &transferred,
            10,
        ) == 0) {}

        self.sequence = 1;
        try self.command(0, &.{}, &.{});
        self.sequence = 1;
        var info: [84]u8 = undefined;
        try self.command(2, &.{}, &info);
        if (getU32(info[8..12]) < 2115) return error.UnsupportedFirmware;
    }

    fn command(self: *Scarlett, command_id: u32, request_data: []const u8, response_data: []u8) !void {
        var request: [128]u8 = @splat(0);
        const request_size = 16 + request_data.len;
        if (request_size > request.len) return error.RequestTooLarge;

        putU32(request[0..4], command_id);
        putU16(request[4..6], @intCast(request_data.len));
        putU16(request[6..8], self.sequence);
        @memcpy(request[16..request_size], request_data);

        const sent = c.libusb_control_transfer(
            self.handle,
            0x21,
            2,
            0,
            control_interface,
            &request,
            @intCast(request_size),
            1000,
        );
        if (sent != request_size) return error.UsbSendFailed;

        try self.waitForAck();

        var response: [128]u8 = undefined;
        const response_size = 16 + response_data.len;
        const received = c.libusb_control_transfer(
            self.handle,
            0xa1,
            3,
            0,
            control_interface,
            &response,
            @intCast(response_size),
            1000,
        );
        if (received != response_size) return error.UsbReceiveFailed;
        if (getU32(response[0..4]) != command_id or
            getU16(response[4..6]) != response_data.len or
            (getU16(response[6..8]) != self.sequence and !(self.sequence == 1 and getU16(response[6..8]) == 0)) or
            getU32(response[8..12]) != 0 or getU32(response[12..16]) != 0)
            return error.InvalidResponse;

        @memcpy(response_data, response[16..response_size]);
        self.sequence +%= 1;
    }

    fn waitForAck(self: *Scarlett) !void {
        var notification: [8]u8 = undefined;
        var attempts: u8 = 0;
        while (attempts < 12) : (attempts += 1) {
            var transferred: c_int = 0;
            const result = c.libusb_interrupt_transfer(
                self.handle,
                notification_endpoint,
                &notification,
                notification.len,
                &transferred,
                100,
            );
            if (result == 0 and transferred == notification.len and (getU32(notification[0..4]) & 1) != 0)
                return;
            if (result != 0 and result != c.LIBUSB_ERROR_TIMEOUT) return error.NotificationFailed;
        }
        return error.CommandTimedOut;
    }
};

fn putU16(out: []u8, value: u16) void {
    out[0] = @truncate(value);
    out[1] = @truncate(value >> 8);
}

fn putU32(out: []u8, value: u32) void {
    out[0] = @truncate(value);
    out[1] = @truncate(value >> 8);
    out[2] = @truncate(value >> 16);
    out[3] = @truncate(value >> 24);
}

fn getU16(input: []const u8) u16 {
    return @as(u16, input[0]) | (@as(u16, input[1]) << 8);
}

fn getU32(input: []const u8) u32 {
    return @as(u32, input[0]) |
        (@as(u32, input[1]) << 8) |
        (@as(u32, input[2]) << 16) |
        (@as(u32, input[3]) << 24);
}
