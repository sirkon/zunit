const std = @import("std");
const siggy = @import("siggy");
const zunit = @import("../root.zig");

const Nano = zunit.Duration(.nanosecs).Siggy;
const Sec = zunit.Duration(.secs).Siggy;
const Mins = zunit.Duration(.mins).Siggy;

const Config = struct { timeout: Sec };
const Parser = siggy.parser(Config);

const NanoConfig = struct { delay: Nano };
const NanoParser = siggy.parser(NanoConfig);

const OptionalConfig = struct { timeout: ?Mins = null };
const OptionalParser = siggy.parser(OptionalConfig);

fn silentPrinter(allocator: std.mem.Allocator, diag: *siggy.Diagnostics) anyerror!void {
    _ = allocator;
    _ = diag;
}

test "duration/siggy: literal and quoted decode" {
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var p: Parser = undefined;
    try p.init(std.testing.allocator, value_arena.allocator(), silentPrinter);

    const literal = try p.parse("timeout = 1h30m\n");
    try std.testing.expectEqual(@as(i64, 5_400_000_000_000), literal.timeout.value());

    const quoted = try p.parse("timeout = \"-5s\"\n");
    try std.testing.expectEqual(@as(i64, -5_000_000_000), quoted.timeout.value());
}

test "duration/siggy: the six suffixes" {
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var p: NanoParser = undefined;
    try p.init(std.testing.allocator, value_arena.allocator(), silentPrinter);

    try std.testing.expectEqual(@as(i64, 5), (try p.parse("delay = 5ns\n")).delay.value());
    try std.testing.expectEqual(@as(i64, 5_000), (try p.parse("delay = 5us\n")).delay.value());
    try std.testing.expectEqual(@as(i64, 5_000_000), (try p.parse("delay = 5ms\n")).delay.value());
    try std.testing.expectEqual(@as(i64, 5_000_000_000), (try p.parse("delay = 5s\n")).delay.value());
    try std.testing.expectEqual(@as(i64, 300_000_000_000), (try p.parse("delay = 5m\n")).delay.value());
    try std.testing.expectEqual(@as(i64, 18_000_000_000_000), (try p.parse("delay = 5h\n")).delay.value());
}

test "duration/siggy: diagnostics for every failure class" {
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var p: Parser = undefined;
    try p.init(std.testing.allocator, value_arena.allocator(), silentPrinter);

    try std.testing.expectError(error.Custom, p.parse("timeout = 5mks\n"));
    try std.testing.expectEqual(error.Custom, p.diagnostic.?.code);
    try std.testing.expectEqualStrings("invalid duration literal '5mks'", p.diagnostic.?.message);

    try std.testing.expectError(error.Custom, p.parse("timeout = 500ms\n"));
    try std.testing.expectEqualStrings("500ms is not a whole number of seconds", p.diagnostic.?.message);
    try std.testing.expectEqual(@as(usize, 10), p.diagnostic.?.offset);

    try std.testing.expectError(error.Custom, p.parse("timeout = 0.5ns\n"));
    try std.testing.expectEqualStrings("0.5ns is not a whole number of seconds", p.diagnostic.?.message);

    try std.testing.expectError(error.UnsupportedShape, p.parse("timeout = { 5s }\n"));
    try std.testing.expectEqualStrings("duration expects a literal or quoted value", p.diagnostic.?.message);
    try std.testing.expectEqual(error.UnsupportedShape, p.diagnostic.?.code);

    try std.testing.expectError(error.UnsupportedShape, p.parse("timeout = 5s { }\n"));
    try std.testing.expectEqual(error.UnsupportedShape, p.diagnostic.?.code);
}

test "duration/siggy: domain overflow diagnostic" {
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var p: NanoParser = undefined;
    try p.init(std.testing.allocator, value_arena.allocator(), silentPrinter);

    try std.testing.expectError(error.Custom, p.parse("delay = 9223372036854775808ns\n"));
    try std.testing.expectEqualStrings("9223372036854775808ns is out of range for nanoseconds", p.diagnostic.?.message);
}

test "duration/siggy: optionality is resolved before decode" {
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var p: OptionalParser = undefined;
    try p.init(std.testing.allocator, value_arena.allocator(), silentPrinter);

    try std.testing.expect((try p.parse("timeout = { }\n")).timeout == null);
    try std.testing.expect((try p.parse("")).timeout == null);
    try std.testing.expectEqual(@as(i64, 120_000_000_000), (try p.parse("timeout = 2m\n")).timeout.?.value());
}

test "duration/siggy: stringify round trip including negatives" {
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var p: Parser = undefined;
    try p.init(std.testing.allocator, value_arena.allocator(), silentPrinter);

    const original = Config{ .timeout = try Sec.fromBase(-5) };
    const text = p.stringify(original);
    try std.testing.expect(std.mem.indexOf(u8, text, "timeout = -5s") != null);

    const reparsed = try p.parse(text);
    try std.testing.expectEqual(original.timeout.value(), reparsed.timeout.value());
}

test "duration/siggy: value survives source arena reset" {
    var source_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var value: Sec = undefined;
    var diag: siggy.Diagnostic = .{ .offset = 7 };

    try value.decode(
        source_arena.allocator(),
        value_arena.allocator(),
        siggy.AstNode{ .quoted = "-2h" },
        &diag,
    );
    source_arena.deinit();

    try std.testing.expectEqual(@as(i64, -7_200_000_000_000), value.value());
}

test "duration/siggy: decode leaves the pre-filled offset untouched" {
    var source_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer source_arena.deinit();
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var value: Sec = undefined;
    var diag: siggy.Diagnostic = .{ .offset = 99 };

    try std.testing.expectError(error.Custom, value.decode(
        source_arena.allocator(),
        value_arena.allocator(),
        siggy.AstNode{ .literal = "500ms" },
        &diag,
    ));
    try std.testing.expectEqual(@as(usize, 99), diag.offset);
    try std.testing.expect(diag.message.len > 0);
}

test "duration/siggy: value surface mirrors dap" {
    const value = try Mins.fromBase(-2);
    try std.testing.expectEqual(@as(i64, -120_000_000_000), value.value());

    const from_raw = try Mins.fromNanos(-120_000_000_000);
    try std.testing.expectEqual(@as(i64, -120_000_000_000), from_raw.value());
    try std.testing.expectError(error.NotMultipleOfBase, Mins.fromNanos(-90_000_000_000));
    try std.testing.expectError(error.UnitOverflow, Mins.fromBase(std.math.maxInt(i64)));
}
