const std = @import("std");
const siggy = @import("siggy");
const zunit = @import("../root.zig");

const MiB = zunit.Volume(.mib).Siggy;
const AnyVolume = zunit.Volume(.b).Siggy;

const Config = struct { cache: MiB };
const Parser = siggy.parser(Config);

const SpellingConfig = struct { cache: AnyVolume };
const SpellingParser = siggy.parser(SpellingConfig);

const OptionalConfig = struct { cache: ?MiB = null };
const OptionalParser = siggy.parser(OptionalConfig);

fn silentPrinter(allocator: std.mem.Allocator, diag: *siggy.Diagnostics) anyerror!void {
    _ = allocator;
    _ = diag;
}

test "volume/siggy: literal and quoted decode" {
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var p: Parser = undefined;
    try p.init(std.testing.allocator, value_arena.allocator(), silentPrinter);

    const literal = try p.parse("cache = 2MiB\n");
    try std.testing.expectEqual(@as(u128, 2097152), literal.cache.value());

    const quoted = try p.parse("cache = \"4MiB\"\n");
    try std.testing.expectEqual(@as(u128, 4194304), quoted.cache.value());
}

test "volume/siggy: every accepted suffix spelling" {
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var p: SpellingParser = undefined;
    try p.init(std.testing.allocator, value_arena.allocator(), silentPrinter);

    const groups = [_]struct { shift: u7, spellings: []const []const u8 }{
        .{ .shift = 10, .spellings = &.{ "2KiB", "2Kib", "2Ki", "2kib", "2ki" } },
        .{ .shift = 20, .spellings = &.{ "2MiB", "2Mib", "2miB", "2Mi", "2mib", "2mi" } },
        .{ .shift = 30, .spellings = &.{ "2GiB", "2Gib", "2Gi", "2gib", "2gi" } },
        .{ .shift = 40, .spellings = &.{ "2TiB", "2Tib", "2Ti", "2tib", "2ti" } },
        .{ .shift = 50, .spellings = &.{ "2PiB", "2Pib", "2Pi", "2pib", "2pi" } },
        .{ .shift = 60, .spellings = &.{ "2EiB", "2Eib", "2Ei", "2eib", "2ei" } },
        .{ .shift = 70, .spellings = &.{ "2ZiB", "2Zib", "2Zi", "2zib", "2zi" } },
        .{ .shift = 80, .spellings = &.{ "2YiB", "2Yib", "2Yi", "2yib", "2yi" } },
    };
    for (groups) |group| {
        for (group.spellings) |text| {
            const parsed = try p.parse(try std.fmt.allocPrint(value_arena.allocator(), "cache = {s}\n", .{text}));
            try std.testing.expectEqual(@as(u128, 2) << group.shift, parsed.cache.value());
        }
    }
}

test "volume/siggy: error classes carry diagnostics" {
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var p: Parser = undefined;
    try p.init(std.testing.allocator, value_arena.allocator(), silentPrinter);

    try std.testing.expectError(error.Custom, p.parse("cache = 2MB\n"));
    try std.testing.expectEqual(error.Custom, p.diagnostic.?.code);
    try std.testing.expectEqualStrings("invalid volume literal '2MB'", p.diagnostic.?.message);
    try std.testing.expectEqual(@as(usize, 8), p.diagnostic.?.offset);

    try std.testing.expectError(error.Custom, p.parse("cache = 512KiB\n"));
    try std.testing.expectEqual(error.Custom, p.diagnostic.?.code);
    try std.testing.expectEqualStrings("512KiB is not a whole number of mebibytes", p.diagnostic.?.message);
    try std.testing.expectEqual(@as(usize, 8), p.diagnostic.?.offset);

    try std.testing.expectError(error.Custom, p.parse("cache = 0.0001MiB\n"));
    try std.testing.expectEqualStrings("0.0001MiB is not a whole number of mebibytes", p.diagnostic.?.message);

    try std.testing.expectError(error.Custom, p.parse("cache = 2MiBx\n"));
    try std.testing.expectEqualStrings("invalid volume literal '2MiBx'", p.diagnostic.?.message);
}

test "volume/siggy: overflow diagnostic" {
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var p: Parser = undefined;
    try p.init(std.testing.allocator, value_arena.allocator(), silentPrinter);

    try std.testing.expectError(error.Custom, p.parse("cache = 340282366920938463463374607431768211455YiB\n"));
    try std.testing.expectEqual(
        error.Custom,
        p.diagnostic.?.code,
    );
    try std.testing.expectEqualStrings(
        "340282366920938463463374607431768211455YiB is out of range for mebibytes",
        p.diagnostic.?.message,
    );
}

test "volume/siggy: an overlong literal is refused early" {
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var p: Parser = undefined;
    try p.init(std.testing.allocator, value_arena.allocator(), silentPrinter);

    const overlong: [4000]u8 = @splat('9');
    const text = try std.fmt.allocPrint(value_arena.allocator(), "cache = {s}\n", .{&overlong});
    try std.testing.expectError(error.Custom, p.parse(text));
    try std.testing.expectEqual(error.Custom, p.diagnostic.?.code);
    try std.testing.expect(p.diagnostic.?.message.len > 0);
}

test "volume/siggy: block and tagged shapes are refused" {
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var p: Parser = undefined;
    try p.init(std.testing.allocator, value_arena.allocator(), silentPrinter);

    try std.testing.expectError(error.UnsupportedShape, p.parse("cache = { 2MiB }\n"));
    try std.testing.expectEqual(error.UnsupportedShape, p.diagnostic.?.code);
    try std.testing.expectEqualStrings("volume expects a literal or quoted value", p.diagnostic.?.message);
    try std.testing.expectEqual(@as(usize, 8), p.diagnostic.?.offset);

    try std.testing.expectError(error.UnsupportedShape, p.parse("cache = 2MiB { }\n"));
    try std.testing.expectEqual(error.UnsupportedShape, p.diagnostic.?.code);
}

test "volume/siggy: optionality is resolved before decode" {
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var p: OptionalParser = undefined;
    try p.init(std.testing.allocator, value_arena.allocator(), silentPrinter);

    try std.testing.expect((try p.parse("cache = { }\n")).cache == null);
    try std.testing.expect((try p.parse("")).cache == null);
    const present = try p.parse("cache = 3MiB\n");
    try std.testing.expectEqual(@as(u128, 3 << 20), present.cache.?.value());
}

test "volume/siggy: stringify round trip" {
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var p: Parser = undefined;
    try p.init(std.testing.allocator, value_arena.allocator(), silentPrinter);

    const original = Config{ .cache = try MiB.fromBase(2) };
    const text = p.stringify(original);
    try std.testing.expect(std.mem.indexOf(u8, text, "cache = 2MiB") != null);

    const reparsed = try p.parse(text);
    try std.testing.expectEqual(original.cache.value(), reparsed.cache.value());
}

test "volume/siggy: value survives source arena reset" {
    var source_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var value: MiB = undefined;
    var diag: siggy.Diagnostic = .{ .offset = 1234 };

    try value.decode(
        source_arena.allocator(),
        value_arena.allocator(),
        siggy.AstNode{ .literal = "2MiB" },
        &diag,
    );
    source_arena.deinit();

    try std.testing.expectEqual(@as(u128, 2097152), value.value());
}

test "volume/siggy: decode leaves the pre-filled offset untouched" {
    var source_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer source_arena.deinit();
    var value_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer value_arena.deinit();

    var value: MiB = undefined;

    var grammar_diag: siggy.Diagnostic = .{ .offset = 42 };
    try std.testing.expectError(error.Custom, value.decode(
        source_arena.allocator(),
        value_arena.allocator(),
        siggy.AstNode{ .quoted = "2MB" },
        &grammar_diag,
    ));
    try std.testing.expectEqual(@as(usize, 42), grammar_diag.offset);
    try std.testing.expect(grammar_diag.message.len > 0);
}

test "volume/siggy: value surface mirrors dap" {
    const value = try MiB.fromBase(2);
    try std.testing.expectEqual(@as(u128, 2097152), value.value());
    try std.testing.expectEqual(@as(u64, 2097152), try value.value64());

    const from_raw = try MiB.fromBytes(2097152);
    try std.testing.expectEqual(@as(u128, 2097152), from_raw.value());
    try std.testing.expectError(error.NotMultipleOfBase, MiB.fromBytes(4096));
    try std.testing.expectError(error.UnitOverflow, MiB.fromBase(std.math.maxInt(u128)));
}
