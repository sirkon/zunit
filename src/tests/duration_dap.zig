const std = @import("std");
const dap = @import("dap");
const zunit = @import("../root.zig");

const Nano = zunit.Duration(.nanosecs).Dap;
const Micro = zunit.Duration(.microsecs).Dap;
const Milli = zunit.Duration(.millisecs).Dap;
const Sec = zunit.Duration(.secs).Dap;
const Mins = zunit.Duration(.mins).Dap;
const Hours = zunit.Duration(.hours).Dap;

const negative_two_minutes = Mins.fromBase(-2) catch unreachable;

test "duration/dap: the six suffixes" {
    try std.testing.expectEqual(@as(i64, 5), (try Nano.decode(std.testing.allocator, "5ns")).value());
    try std.testing.expectEqual(@as(i64, 5_000), (try Nano.decode(std.testing.allocator, "5us")).value());
    try std.testing.expectEqual(@as(i64, 5_000_000), (try Nano.decode(std.testing.allocator, "5ms")).value());
    try std.testing.expectEqual(@as(i64, 5_000_000_000), (try Nano.decode(std.testing.allocator, "5s")).value());
    try std.testing.expectEqual(@as(i64, 300_000_000_000), (try Nano.decode(std.testing.allocator, "5m")).value());
    try std.testing.expectEqual(@as(i64, 18_000_000_000_000), (try Nano.decode(std.testing.allocator, "5h")).value());

    try std.testing.expectEqual(@as(i64, 5), (try Nano.decode(std.testing.allocator, "5")).value());
}

test "duration/dap: rejected suffix spellings" {
    const rejected = [_][]const u8{
        "5mks",       "5M",         "5H", "5S", "5MS", "5NS", "5US",
        "5\xc2\xb5s", "5\xce\xbcs",
    };
    for (rejected) |text| {
        try std.testing.expectError(error.InvalidWire, Nano.decode(std.testing.allocator, text));
    }
}

test "duration/dap: base multiple requirement" {
    try std.testing.expectError(error.InvalidValue, Sec.decode(std.testing.allocator, "500ms"));
    try std.testing.expectEqual(@as(i64, 1_500_000_000), (try Milli.decode(std.testing.allocator, "1500ms")).value());
    try std.testing.expectEqual(@as(i64, 5_400_000_000_000), (try Sec.decode(std.testing.allocator, "1h30m")).value());

    try std.testing.expectError(error.InvalidValue, Mins.decode(std.testing.allocator, "90s"));
    try std.testing.expectEqual(@as(i64, 120_000_000_000), (try Mins.decode(std.testing.allocator, "120s")).value());
    try std.testing.expectEqual(@as(i64, -120_000_000_000), (try Mins.decode(std.testing.allocator, "-120s")).value());
    try std.testing.expectError(error.InvalidValue, Mins.decode(std.testing.allocator, "-90s"));

    try std.testing.expectError(error.InvalidValue, Hours.decode(std.testing.allocator, "90m"));
}

test "duration/dap: combinations" {
    try std.testing.expectEqual(@as(i64, 5_400_000_000_000), (try Nano.decode(std.testing.allocator, "1.5h")).value());
    try std.testing.expectEqual(@as(i64, 5_430_000_000_000), (try Nano.decode(std.testing.allocator, "1h30.5m")).value());
    try std.testing.expectEqual(
        @as(i64, 9_910_500_000_000),
        (try Milli.decode(std.testing.allocator, "2h45m10s500ms")).value(),
    );
    try std.testing.expectEqual(
        @as(i64, 1_000_000_001),
        (try Nano.decode(std.testing.allocator, "1.000000001s")).value(),
    );

    const rejected = [_][]const u8{
        "30m1h",  "1m30m", "1h30", "1h-30m", "1h+30m", "--5s", "1h30.5m2h", "1h30s20m", "1h1h", "1ms1ns1s",
        "1h 30m", "5 s",   " 5s",  "",       "-",      "+",
    };
    for (rejected) |text| {
        try std.testing.expectError(error.InvalidWire, Nano.decode(std.testing.allocator, text));
    }
}

test "duration/dap: decimal exactness" {
    try std.testing.expectEqual(@as(i64, 1_500), (try Nano.decode(std.testing.allocator, "1.5us")).value());
    try std.testing.expectError(error.InvalidValue, Micro.decode(std.testing.allocator, "1.5us"));
    try std.testing.expectError(error.InvalidValue, Nano.decode(std.testing.allocator, "1.5ns"));
    try std.testing.expectError(error.InvalidValue, Nano.decode(std.testing.allocator, "0.5ns"));
    try std.testing.expectError(error.InvalidWire, Nano.decode(std.testing.allocator, "1.5"));
}

test "duration/dap: bare zero under every base" {
    const bases = [_]zunit.DurationBase{ .nanosecs, .microsecs, .millisecs, .secs, .mins, .hours };
    inline for (bases) |base| {
        try std.testing.expectEqual(
            @as(i64, 0),
            (try zunit.Duration(base).Dap.decode(std.testing.allocator, "0")).value(),
        );
    }
}

test "duration/dap: inexact decimals are value errors under every base" {
    const bases = [_]zunit.DurationBase{ .nanosecs, .microsecs, .millisecs, .secs, .mins, .hours };
    inline for (bases) |base| {
        try std.testing.expectError(
            error.InvalidValue,
            zunit.Duration(base).Dap.decode(std.testing.allocator, "0.5ns"),
        );
    }
}

test "duration/dap: zero and signs" {
    const zeroes = [_][]const u8{ "0", "0h0m", "-0", "+0", "-0s", "+0ns" };
    for (zeroes) |text| {
        const value = try Nano.decode(std.testing.allocator, text);
        try std.testing.expectEqual(@as(i64, 0), value.value());
    }

    try std.testing.expectEqual(@as(i64, -5_000_000_000), (try Sec.decode(std.testing.allocator, "-5s")).value());
    try std.testing.expectEqual(@as(i64, -5_400_000_000_000), (try Sec.decode(std.testing.allocator, "-1h30m")).value());
    try std.testing.expectEqual(@as(i64, -30), (try Nano.decode(std.testing.allocator, "-30")).value());
    try std.testing.expectEqual(@as(i64, 7_000_000_000), (try Sec.decode(std.testing.allocator, "007s")).value());
    try std.testing.expectEqual(@as(i64, -5_000), (try Nano.decode(std.testing.allocator, "-5us")).value());
}

test "duration/dap: domain boundaries" {
    try std.testing.expectEqual(
        std.math.minInt(i64),
        (try Nano.decode(std.testing.allocator, "-9223372036854775808ns")).value(),
    );
    try std.testing.expectEqual(
        std.math.maxInt(i64),
        (try Nano.decode(std.testing.allocator, "9223372036854775807ns")).value(),
    );
    try std.testing.expectError(
        error.InvalidValue,
        Nano.decode(std.testing.allocator, "9223372036854775808ns"),
    );
    try std.testing.expectError(
        error.InvalidValue,
        Nano.decode(std.testing.allocator, "-9223372036854775809ns"),
    );

    const overlong: [4000]u8 = @splat('9');
    try std.testing.expectError(error.InvalidValue, Nano.decode(std.testing.allocator, &overlong));

    try std.testing.expectError(
        error.InvalidValue,
        Nano.decode(std.testing.allocator, "340282366920938463463374607431768211455h"),
    );
}

test "duration/dap: constructors" {
    try std.testing.expectEqual(@as(i64, 2_000_000_000), (try Sec.fromBase(2)).value());
    try std.testing.expectEqual(@as(i64, -120_000_000_000), (try Mins.fromBase(-2)).value());
    try std.testing.expectEqual(@as(i64, 18_000_000_000_000), (try Hours.fromBase(5)).value());

    try std.testing.expectError(error.UnitOverflow, Hours.fromBase(std.math.maxInt(i64)));
    try std.testing.expectError(error.UnitOverflow, Mins.fromBase(std.math.maxInt(i64)));

    try std.testing.expectEqual(@as(i64, 2_000_000_000), (try Sec.fromNanos(2_000_000_000)).value());
    try std.testing.expectError(error.NotMultipleOfBase, Sec.fromNanos(1_500_000_000));
    try std.testing.expectEqual(std.math.minInt(i64), (try Nano.fromNanos(std.math.minInt(i64))).value());
}

test "duration/dap: canonical encoding and round trip" {
    const cases = [_]struct { base: zunit.DurationBase, raw: i64, text: []const u8 }{
        .{ .base = .mins, .raw = 120_000_000_000, .text = "2m" },
        .{ .base = .mins, .raw = -120_000_000_000, .text = "-2m" },
        .{ .base = .nanosecs, .raw = 5, .text = "5ns" },
        .{ .base = .microsecs, .raw = 5_000, .text = "5us" },
        .{ .base = .millisecs, .raw = 2_000_000, .text = "2ms" },
        .{ .base = .secs, .raw = 0, .text = "0s" },
        .{ .base = .hours, .raw = -7_200_000_000_000, .text = "-2h" },
        .{ .base = .nanosecs, .raw = std.math.minInt(i64), .text = "-9223372036854775808ns" },
    };
    inline for (cases) |case| {
        const V = zunit.Duration(case.base).Dap;
        const value = try V.fromNanos(case.raw);
        const text = try value.encode(std.testing.allocator);
        defer std.testing.allocator.free(text);
        try std.testing.expectEqualStrings(case.text, text);

        const reparsed = try V.decode(std.testing.allocator, text);
        try std.testing.expectEqual(case.raw, reparsed.value());
    }
}

test "duration/dap: error split" {
    try std.testing.expectError(error.InvalidWire, Sec.decode(std.testing.allocator, "5mks"));
    try std.testing.expectError(error.InvalidWire, Sec.decode(std.testing.allocator, "1h30"));
    try std.testing.expectError(error.InvalidValue, Sec.decode(std.testing.allocator, "500ms"));
    try std.testing.expectError(error.InvalidValue, Sec.decode(std.testing.allocator, "0.5ns"));
    try std.testing.expectError(error.InvalidValue, Nano.decode(std.testing.allocator, "-9223372036854775809ns"));
}

const Def = .{
    .timeout = dap.Flag(Mins){
        .default = dap.defaultValue(Mins, negative_two_minutes),
        .help = "Timeout.",
    },
    .delay = dap.Argument(Sec){ .help = "Delay." },
};
const CLI = dap.generate(dap.App{ .name = "zunit-duration", .help = "Duration test." }, Def);

test "duration/dap: flag and argument decode, negative default, help and deinit" {
    var diag: dap.Diag = .{};
    defer diag.deinit(std.testing.allocator);

    var cli = try CLI.parse(std.testing.allocator, std.process.Environ.empty, &.{ "--timeout", "5m", "2s" }, &diag);
    defer CLI.deinit(&cli, std.testing.allocator);
    try std.testing.expectEqual(@as(i64, 300_000_000_000), cli.timeout.value());
    try std.testing.expectEqual(@as(i64, 2_000_000_000), cli.delay.value());

    var default_cli = try CLI.parse(std.testing.allocator, std.process.Environ.empty, &.{"2s"}, &diag);
    defer CLI.deinit(&default_cli, std.testing.allocator);
    try std.testing.expectEqual(@as(i64, -120_000_000_000), default_cli.timeout.value());

    var data = try CLI.helpData(std.testing.allocator);
    defer data.deinit(std.testing.allocator);
    var rendered: ?[]const u8 = null;
    for (data.flag_groups) |group| {
        for (group.flags) |flag| {
            if (std.mem.eql(u8, flag.name, "timeout")) rendered = flag.default;
        }
    }
    try std.testing.expectEqualStrings("-2m", rendered orelse return error.TestUnexpectedResult);
}
