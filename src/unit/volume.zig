const std = @import("std");
const core = @import("core.zig");

const Self = @This();

pub const VolumeBase = enum { b, kib, mib, gib, tib, pib, eib, zib, yib };

fn shift(base: VolumeBase) u7 {
    return switch (base) {
        .b => 0,
        .kib => 10,
        .mib => 20,
        .gib => 30,
        .tib => 40,
        .pib => 50,
        .eib => 60,
        .zib => 70,
        .yib => 80,
    };
}

pub fn factor(base: VolumeBase) u128 {
    return @as(u128, 1) << shift(base);
}

pub fn suffix(base: VolumeBase) []const u8 {
    return switch (base) {
        .b => "",
        .kib => "KiB",
        .mib => "MiB",
        .gib => "GiB",
        .tib => "TiB",
        .pib => "PiB",
        .eib => "EiB",
        .zib => "ZiB",
        .yib => "YiB",
    };
}

pub fn noun(base: VolumeBase) []const u8 {
    return switch (base) {
        .b => "bytes",
        .kib => "kibibytes",
        .mib => "mebibytes",
        .gib => "gibibytes",
        .tib => "tebibytes",
        .pib => "pebibytes",
        .eib => "exbibytes",
        .zib => "zebibytes",
        .yib => "yobibytes",
    };
}

fn suffixShift(rest: []const u8) ?u7 {
    if (rest.len < 2 or rest.len > 3) return null;
    const index: u7 = switch (rest[0]) {
        'K', 'k' => 1,
        'M', 'm' => 2,
        'G', 'g' => 3,
        'T', 't' => 4,
        'P', 'p' => 5,
        'E', 'e' => 6,
        'Z', 'z' => 7,
        'Y', 'y' => 8,
        else => return null,
    };
    if (rest[1] != 'i') return null;
    if (rest.len == 3 and rest[2] != 'b' and rest[2] != 'B') return null;
    return index * 10;
}

pub fn parse(base: VolumeBase, input: []const u8) core.Error!u128 {
    const component = core.scanComponent(input, 0) catch |err| return switch (err) {
        error.InvalidWire => error.InvalidWire,
        error.Overflow => error.Overflow,
    };

    var magnitude_shift: u7 = 0;
    if (component.end < input.len) {
        magnitude_shift = suffixShift(input[component.end..]) orelse return error.InvalidWire;
    } else if (component.scale != 0) {
        return error.InvalidWire;
    }

    const unit_factor: u128 = if (magnitude_shift == 0) 1 else @as(u128, 1) << magnitude_shift;
    const value = try core.scaleToInteger(component.mantissa, component.scale, unit_factor);
    if (value % factor(base) != 0) return error.NotMultiple;
    return value;
}

pub fn encode(base: VolumeBase, raw: u128, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    const count = raw / factor(base);
    if (base == .b) return std.fmt.allocPrint(allocator, "{d}", .{count});
    return std.fmt.allocPrint(allocator, "{d}{s}", .{ count, suffix(base) });
}

fn fromBase(base: VolumeBase, n: u128) error{UnitOverflow}!u128 {
    return std.math.mul(u128, n, factor(base)) catch error.UnitOverflow;
}

fn fromBytes(base: VolumeBase, raw: u128) error{NotMultipleOfBase}!u128 {
    if (raw % factor(base) != 0) return error.NotMultipleOfBase;
    return raw;
}

fn value64(raw: u128) error{UnitOverflow}!u64 {
    if (raw > std.math.maxInt(u64)) return error.UnitOverflow;
    return @intCast(raw);
}

const kind = "volume";

pub fn Namespace(comptime base: VolumeBase) type {
    return struct {
        pub const Dap = struct {
            raw: u128,

            pub fn decode(allocator: std.mem.Allocator, data: []const u8) error{ InvalidWire, InvalidValue }!Dap {
                _ = allocator;
                const raw = parse(base, data) catch |err| return switch (err) {
                    error.InvalidWire => error.InvalidWire,
                    else => error.InvalidValue,
                };
                return .{ .raw = raw };
            }

            pub fn encode(self: *const Dap, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
                return Self.encode(base, self.raw, allocator);
            }

            pub fn deinit(self: *Dap, allocator: std.mem.Allocator) void {
                _ = self;
                _ = allocator;
            }

            pub fn value(self: Dap) u128 {
                return self.raw;
            }

            pub fn value64(self: Dap) error{UnitOverflow}!u64 {
                return Self.value64(self.raw);
            }

            pub fn fromBase(n: u128) error{UnitOverflow}!Dap {
                return .{ .raw = try Self.fromBase(base, n) };
            }

            pub fn fromBytes(raw: u128) error{NotMultipleOfBase}!Dap {
                return .{ .raw = try Self.fromBytes(base, raw) };
            }
        };

        pub const Siggy = struct {
            raw: u128,

            pub fn decode(
                self: *Siggy,
                source_arena: std.mem.Allocator,
                value_arena: std.mem.Allocator,
                node: anytype,
                diag: anytype,
            ) anyerror!void {
                _ = value_arena;
                const text: []const u8 = switch (node) {
                    .literal => |text| text,
                    .quoted => |text| text,
                    else => return core.failShape(source_arena, diag, kind),
                };
                self.raw = parse(base, text) catch |err| {
                    return core.fail(source_arena, diag, err, text, kind, noun(base));
                };
            }

            pub fn encode(self: *const Siggy, allocator: std.mem.Allocator) anyerror![]const u8 {
                return Self.encode(base, self.raw, allocator);
            }

            pub fn value(self: Siggy) u128 {
                return self.raw;
            }

            pub fn value64(self: Siggy) error{UnitOverflow}!u64 {
                return Self.value64(self.raw);
            }

            pub fn fromBase(n: u128) error{UnitOverflow}!Siggy {
                return .{ .raw = try Self.fromBase(base, n) };
            }

            pub fn fromBytes(raw: u128) error{NotMultipleOfBase}!Siggy {
                return .{ .raw = try Self.fromBytes(base, raw) };
            }
        };
    };
}
