const std = @import("std");

pub const Error = error{
    InvalidWire,
    Inexact,
    NotMultiple,
    Overflow,
};

pub const Component = struct {
    mantissa: u128,
    scale: u32,
    end: usize,
};

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

pub fn scanComponent(input: []const u8, start: usize) error{ InvalidWire, Overflow }!Component {
    if (start >= input.len) return error.InvalidWire;

    var mantissa: u128 = 0;
    var i = start;
    var int_digits: usize = 0;
    while (i < input.len and isDigit(input[i])) : (i += 1) {
        mantissa = std.math.mul(u128, mantissa, 10) catch return error.Overflow;
        mantissa = std.math.add(u128, mantissa, input[i] - '0') catch return error.Overflow;
        int_digits += 1;
    }
    if (int_digits == 0) return error.InvalidWire;

    var scale: u32 = 0;
    if (i < input.len and input[i] == '.') {
        i += 1;
        var frac_digits: usize = 0;
        while (i < input.len and isDigit(input[i])) : (i += 1) {
            mantissa = std.math.mul(u128, mantissa, 10) catch return error.Overflow;
            mantissa = std.math.add(u128, mantissa, input[i] - '0') catch return error.Overflow;
            scale += 1;
            frac_digits += 1;
        }
        if (frac_digits == 0) return error.InvalidWire;
    }

    return .{ .mantissa = mantissa, .scale = scale, .end = i };
}

pub fn scaleToInteger(mantissa: u128, scale: u32, factor: u128) Error!u128 {
    if (mantissa == 0) return 0;

    var num = mantissa;
    var twos = scale;
    var fives = scale;

    while (twos > 0 and num % 2 == 0) : (twos -= 1) num /= 2;
    while (fives > 0 and num % 5 == 0) : (fives -= 1) num /= 5;

    var f = factor;
    while (twos > 0 and f % 2 == 0) : (twos -= 1) f /= 2;
    while (fives > 0 and f % 5 == 0) : (fives -= 1) f /= 5;

    if (twos != 0 or fives != 0) return error.Inexact;
    return std.math.mul(u128, num, f) catch error.Overflow;
}

pub fn checkedAdd(a: u128, b: u128) Error!u128 {
    return std.math.add(u128, a, b) catch error.Overflow;
}

pub fn fail(
    allocator: std.mem.Allocator,
    diag: anytype,
    err: Error,
    text: []const u8,
    kind: []const u8,
    noun: []const u8,
) anyerror {
    diag.code = error.Custom;
    diag.message = switch (err) {
        error.InvalidWire => std.fmt.allocPrint(allocator, "invalid {s} literal '{s}'", .{ kind, text }),
        error.Inexact, error.NotMultiple => std.fmt.allocPrint(
            allocator,
            "{s} is not a whole number of {s}",
            .{ text, noun },
        ),
        error.Overflow => std.fmt.allocPrint(allocator, "{s} is out of range for {s}", .{ text, noun }),
    } catch "";
    return error.Custom;
}

pub fn failShape(allocator: std.mem.Allocator, diag: anytype, kind: []const u8) anyerror {
    diag.code = error.UnsupportedShape;
    diag.message = std.fmt.allocPrint(allocator, "{s} expects a literal or quoted value", .{kind}) catch "";
    return error.UnsupportedShape;
}

test "core: scan plain and decimal components" {
    const a = try scanComponent("2097152", 0);
    try std.testing.expectEqual(@as(u128, 2097152), a.mantissa);
    try std.testing.expectEqual(@as(u32, 0), a.scale);
    try std.testing.expectEqual(@as(usize, 7), a.end);

    const b = try scanComponent("1.5MiB", 0);
    try std.testing.expectEqual(@as(u128, 15), b.mantissa);
    try std.testing.expectEqual(@as(u32, 1), b.scale);
    try std.testing.expectEqual(@as(usize, 3), b.end);

    const c = try scanComponent("007", 0);
    try std.testing.expectEqual(@as(u128, 7), c.mantissa);
}

test "core: scan rejects broken decimals" {
    try std.testing.expectError(error.InvalidWire, scanComponent("", 0));
    try std.testing.expectError(error.InvalidWire, scanComponent(".5", 0));
    try std.testing.expectError(error.InvalidWire, scanComponent("1.", 0));
    try std.testing.expectError(error.InvalidWire, scanComponent("1..5", 0));

    const max = try scanComponent("340282366920938463463374607431768211455", 0);
    try std.testing.expectEqual(std.math.maxInt(u128), max.mantissa);

    const overlong: [50]u8 = @splat('9');
    try std.testing.expectError(error.Overflow, scanComponent(&overlong, 0));
}

test "core: exact decimal division" {
    try std.testing.expectEqual(@as(u128, 1572864), try scaleToInteger(15, 1, 1 << 20));
    try std.testing.expectEqual(@as(u128, 0), try scaleToInteger(0, 7, 1 << 20));
    try std.testing.expectError(error.Inexact, scaleToInteger(1, 4, 1 << 20));
    try std.testing.expectError(error.Inexact, scaleToInteger(1, 1, 1));
    try std.testing.expectEqual(@as(u128, 1), try scaleToInteger(5, 1, 2));
}

test "core: scaleToInteger matches exact rational division" {
    const factors = [_]u128{ 1, 2, 5, 10, 1_000, 1 << 20, 3_600_000_000_000 };
    var mantissa: u128 = 0;
    while (mantissa <= 64) : (mantissa += 1) {
        var scale: u32 = 0;
        while (scale <= 3) : (scale += 1) {
            var denominator: u128 = 1;
            var i: u32 = 0;
            while (i < scale) : (i += 1) denominator *= 10;
            for (factors) |factor| {
                const numerator = mantissa * factor;
                if (numerator % denominator == 0) {
                    try std.testing.expectEqual(numerator / denominator, try scaleToInteger(mantissa, scale, factor));
                } else {
                    try std.testing.expectError(error.Inexact, scaleToInteger(mantissa, scale, factor));
                }
            }
        }
    }
}

test "core: huge scale is rejected without computing 10^scale" {
    try std.testing.expectEqual(@as(u128, 0), try scaleToInteger(0, 4096, 1 << 80));
    try std.testing.expectError(error.Inexact, scaleToInteger(1, 4096, 1 << 80));
}

test "core: checked add overflow" {
    try std.testing.expectEqual(@as(u128, 3), try checkedAdd(1, 2));
    try std.testing.expectError(error.Overflow, checkedAdd(std.math.maxInt(u128), 1));
}
