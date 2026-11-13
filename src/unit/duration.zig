const std = @import("std");
const core = @import("core.zig");

const Self = @This();

pub const DurationBase = enum { nanosecs, microsecs, millisecs, secs, mins, hours };

pub fn factor(base: DurationBase) u128 {
    return switch (base) {
        .nanosecs => 1,
        .microsecs => 1_000,
        .millisecs => 1_000_000,
        .secs => 1_000_000_000,
        .mins => 60_000_000_000,
        .hours => 3_600_000_000_000,
    };
}

pub fn suffix(base: DurationBase) []const u8 {
    return switch (base) {
        .nanosecs => "ns",
        .microsecs => "us",
        .millisecs => "ms",
        .secs => "s",
        .mins => "m",
        .hours => "h",
    };
}

pub fn noun(base: DurationBase) []const u8 {
    return switch (base) {
        .nanosecs => "nanoseconds",
        .microsecs => "microseconds",
        .millisecs => "milliseconds",
        .secs => "seconds",
        .mins => "minutes",
        .hours => "hours",
    };
}

const Suffix = struct {
    rank: u8,
    factor: u128,
    len: usize,
};

fn suffixAt(rest: []const u8) ?Suffix {
    if (rest.len >= 2) {
        if (std.mem.eql(u8, rest[0..2], "ns")) return .{ .rank = 0, .factor = 1, .len = 2 };
        if (std.mem.eql(u8, rest[0..2], "us")) return .{ .rank = 1, .factor = 1_000, .len = 2 };
        if (std.mem.eql(u8, rest[0..2], "ms")) return .{ .rank = 2, .factor = 1_000_000, .len = 2 };
    }
    if (rest.len >= 1) {
        return switch (rest[0]) {
            's' => .{ .rank = 3, .factor = 1_000_000_000, .len = 1 },
            'm' => .{ .rank = 4, .factor = 60_000_000_000, .len = 1 },
            'h' => .{ .rank = 5, .factor = 3_600_000_000_000, .len = 1 },
            else => null,
        };
    }
    return null;
}

pub fn parse(base: DurationBase, input: []const u8) core.Error!i64 {
    if (input.len == 0) return error.InvalidWire;

    var i: usize = 0;
    var negative = false;
    if (input[0] == '-' or input[0] == '+') {
        negative = input[0] == '-';
        i = 1;
        if (i == input.len) return error.InvalidWire;
    }

    var total: u128 = 0;
    var previous_rank: ?u8 = null;
    var components: usize = 0;

    while (i < input.len) {
        const component = core.scanComponent(input, i) catch |err| return switch (err) {
            error.InvalidWire => error.InvalidWire,
            error.Overflow => error.Overflow,
        };
        i = component.end;

        var unit_factor: u128 = 1;
        if (i < input.len) {
            const s = suffixAt(input[i..]) orelse return error.InvalidWire;
            if (previous_rank) |previous| {
                if (s.rank >= previous) return error.InvalidWire;
            }
            unit_factor = s.factor;
            previous_rank = s.rank;
            i += s.len;
        } else {
            if (components != 0) return error.InvalidWire;
            if (component.scale != 0) return error.InvalidWire;
            previous_rank = 0;
        }

        const unit = try core.scaleToInteger(component.mantissa, component.scale, unit_factor);
        total = try core.checkedAdd(total, unit);
        components += 1;
    }
    if (components == 0) return error.InvalidWire;

    if (total % factor(base) != 0) return error.NotMultiple;

    const max_positive: u128 = std.math.maxInt(i64);
    const max_negative: u128 = @as(u128, std.math.maxInt(i64)) + 1;
    if (negative) {
        if (total > max_negative) return error.Overflow;
        if (total == max_negative) return std.math.minInt(i64);
        return -@as(i64, @intCast(total));
    }
    if (total > max_positive) return error.Overflow;
    return @intCast(total);
}

pub fn encode(base: DurationBase, raw: i64, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    const count = @divTrunc(raw, @as(i64, @intCast(factor(base))));
    return std.fmt.allocPrint(allocator, "{d}{s}", .{ count, suffix(base) });
}

fn fromBase(base: DurationBase, n: i64) error{UnitOverflow}!i64 {
    const raw = std.math.mul(i128, @as(i128, n), @as(i128, @intCast(factor(base)))) catch
        return error.UnitOverflow;
    if (raw < std.math.minInt(i64) or raw > std.math.maxInt(i64)) return error.UnitOverflow;
    return @intCast(raw);
}

fn fromNanos(base: DurationBase, raw: i64) error{NotMultipleOfBase}!i64 {
    const base_factor: i64 = @intCast(factor(base));
    if (@rem(raw, base_factor) != 0) return error.NotMultipleOfBase;
    return raw;
}

const kind = "duration";

pub fn Namespace(comptime base: DurationBase) type {
    return struct {
        pub const Dap = struct {
            raw: i64,

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

            pub fn value(self: Dap) i64 {
                return self.raw;
            }

            pub fn fromBase(n: i64) error{UnitOverflow}!Dap {
                return .{ .raw = try Self.fromBase(base, n) };
            }

            pub fn fromNanos(raw: i64) error{NotMultipleOfBase}!Dap {
                return .{ .raw = try Self.fromNanos(base, raw) };
            }
        };

        pub const Siggy = struct {
            raw: i64,

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

            pub fn value(self: Siggy) i64 {
                return self.raw;
            }

            pub fn fromBase(n: i64) error{UnitOverflow}!Siggy {
                return .{ .raw = try Self.fromBase(base, n) };
            }

            pub fn fromNanos(raw: i64) error{NotMultipleOfBase}!Siggy {
                return .{ .raw = try Self.fromNanos(base, raw) };
            }
        };
    };
}
