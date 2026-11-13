const std = @import("std");
const dap = @import("dap");
const zunit = @import("../root.zig");

const Byte = zunit.Volume(.b).Dap;
const MiB = zunit.Volume(.mib).Dap;

const two_mib = MiB.fromBase(2) catch unreachable;

test "volume/dap: every accepted suffix spelling for every base" {
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
            const value = try Byte.decode(std.testing.allocator, text);
            try std.testing.expectEqual(@as(u128, 2) << group.shift, value.value());
        }
    }
}

test "volume/dap: canonical rejections" {
    const rejected = [_][]const u8{ "2M", "2Mb", "2MB", "2MIB", "2KIB", "2KI", "2mIB", "2iB", "2MiBB" };
    for (rejected) |text| {
        try std.testing.expectError(error.InvalidWire, Byte.decode(std.testing.allocator, text));
    }
}

test "volume/dap: base multiple requirement" {
    try std.testing.expectEqual(@as(u128, 2097152), (try MiB.decode(std.testing.allocator, "2MiB")).value());
    try std.testing.expectEqual(@as(u128, 2097152), (try MiB.decode(std.testing.allocator, "2097152")).value());
    try std.testing.expectEqual(@as(u128, 2097152), (try MiB.decode(std.testing.allocator, "2.0MiB")).value());

    try std.testing.expectError(error.InvalidValue, MiB.decode(std.testing.allocator, "512KiB"));
    try std.testing.expectError(error.InvalidValue, MiB.decode(std.testing.allocator, "4096"));
    try std.testing.expectError(error.InvalidValue, MiB.decode(std.testing.allocator, "1.5MiB"));
}

test "volume/dap: decimal exactness" {
    try std.testing.expectEqual(@as(u128, 1572864), (try Byte.decode(std.testing.allocator, "1.5MiB")).value());
    try std.testing.expectEqual(
        @as(u128, 1572864),
        (try zunit.Volume(.kib).Dap.decode(std.testing.allocator, "1.5MiB")).value(),
    );
    try std.testing.expectEqual(@as(u128, 2048), (try Byte.decode(std.testing.allocator, "2.0KiB")).value());
    try std.testing.expectError(error.InvalidValue, Byte.decode(std.testing.allocator, "0.0001MiB"));
    try std.testing.expectError(error.InvalidValue, MiB.decode(std.testing.allocator, "0.0001MiB"));
}

test "volume/dap: bare zero under every base" {
    const bases = [_]zunit.VolumeBase{ .b, .kib, .mib, .gib, .tib, .pib, .eib, .zib, .yib };
    inline for (bases) |base| {
        try std.testing.expectEqual(
            @as(u128, 0),
            (try zunit.Volume(base).Dap.decode(std.testing.allocator, "0")).value(),
        );
    }
}

test "volume/dap: inexact decimals are value errors under every base" {
    const bases = [_]zunit.VolumeBase{ .b, .kib, .mib, .gib, .tib, .pib, .eib, .zib, .yib };
    inline for (bases) |base| {
        try std.testing.expectError(
            error.InvalidValue,
            zunit.Volume(base).Dap.decode(std.testing.allocator, "0.0001MiB"),
        );
    }
}

test "volume/dap: zero everywhere" {
    const bases = [_]zunit.VolumeBase{ .b, .kib, .mib, .gib, .tib, .pib, .eib, .zib, .yib };
    const spellings = [_][]const u8{ "0", "0KiB", "0MiB", "0GiB", "0TiB", "0PiB", "0EiB", "0ZiB", "0YiB" };
    inline for (bases, spellings) |base, text| {
        const value = try zunit.Volume(base).Dap.decode(std.testing.allocator, text);
        try std.testing.expectEqual(@as(u128, 0), value.value());
        try std.testing.expectEqual(@as(u64, 0), try value.value64());
    }
}

test "volume/dap: grammar edges" {
    const errors = [_][]const u8{ "", "1.5", "-5", "+5", "2 MiB", "MiB", ".5MiB", "1.MiB", "2MiBx" };
    for (errors) |text| {
        try std.testing.expectError(error.InvalidWire, Byte.decode(std.testing.allocator, text));
    }
    try std.testing.expectEqual(@as(u128, 7), (try Byte.decode(std.testing.allocator, "007")).value());
}

test "volume/dap: domain and literal overflow" {
    const max = (try Byte.decode(std.testing.allocator, "340282366920938463463374607431768211455")).value();
    try std.testing.expectEqual(std.math.maxInt(u128), max);
    try std.testing.expectError(error.UnitOverflow, (try Byte.decode(std.testing.allocator, "340282366920938463463374607431768211455")).value64());

    try std.testing.expectError(
        error.InvalidValue,
        Byte.decode(std.testing.allocator, "340282366920938463463374607431768211456"),
    );
    try std.testing.expectError(
        error.InvalidValue,
        Byte.decode(std.testing.allocator, "340282366920938463463374607431768211455YiB"),
    );

    const overlong: [4000]u8 = @splat('9');
    try std.testing.expectError(error.InvalidValue, Byte.decode(std.testing.allocator, &overlong));
}

test "volume/dap: value64 boundaries" {
    const max = try Byte.fromBase(std.math.maxInt(u64));
    try std.testing.expectEqual(std.math.maxInt(u64), try max.value64());
    const over = try Byte.fromBase(@as(u128, std.math.maxInt(u64)) + 1);
    try std.testing.expectError(error.UnitOverflow, over.value64());
}

test "volume/dap: constructors" {
    const built = try MiB.fromBase(2);
    try std.testing.expectEqual(@as(u128, 2097152), built.value());
    try std.testing.expectEqual(@as(u128, 2097152), (try MiB.fromBytes(2097152)).value());
    try std.testing.expectError(error.NotMultipleOfBase, MiB.fromBytes(4096));
    try std.testing.expectError(error.UnitOverflow, MiB.fromBase(std.math.maxInt(u128)));
}

test "volume/dap: canonical encoding and round trip" {
    const cases = [_]struct { base: zunit.VolumeBase, raw: u128, text: []const u8 }{
        .{ .base = .b, .raw = 2097152, .text = "2097152" },
        .{ .base = .kib, .raw = 2097152, .text = "2048KiB" },
        .{ .base = .mib, .raw = 2097152, .text = "2MiB" },
        .{ .base = .gib, .raw = 3 << 30, .text = "3GiB" },
        .{ .base = .tib, .raw = 1 << 40, .text = "1TiB" },
        .{ .base = .pib, .raw = 1 << 50, .text = "1PiB" },
        .{ .base = .eib, .raw = 1 << 60, .text = "1EiB" },
        .{ .base = .zib, .raw = 1 << 70, .text = "1ZiB" },
        .{ .base = .yib, .raw = 1 << 80, .text = "1YiB" },
        .{ .base = .mib, .raw = 0, .text = "0MiB" },
    };
    inline for (cases) |case| {
        const V = zunit.Volume(case.base).Dap;
        const value = try V.fromBytes(case.raw);
        const text = try value.encode(std.testing.allocator);
        defer std.testing.allocator.free(text);
        try std.testing.expectEqualStrings(case.text, text);

        const reparsed = try V.decode(std.testing.allocator, text);
        try std.testing.expectEqual(case.raw, reparsed.value());
    }
}

test "volume/dap: error split" {
    try std.testing.expectError(error.InvalidWire, MiB.decode(std.testing.allocator, "2MB"));
    try std.testing.expectError(error.InvalidValue, MiB.decode(std.testing.allocator, "512KiB"));
    try std.testing.expectError(error.InvalidValue, MiB.decode(std.testing.allocator, "0.1MiB"));
    try std.testing.expectError(error.InvalidValue, MiB.decode(std.testing.allocator, "340282366920938463463374607431768211455YiB"));
}

const Def = .{
    .cache = dap.Flag(MiB){
        .default = dap.defaultValue(MiB, two_mib),
        .help = "Cache size.",
    },
    .path = dap.Argument(Byte){ .help = "File to read." },
};
const CLI = dap.generate(dap.App{ .name = "zunit-test", .help = "Test app." }, Def);

test "volume/dap: flag and argument decode, defaults, help and deinit" {
    var diag: dap.Diag = .{};
    defer diag.deinit(std.testing.allocator);

    var cli = try CLI.parse(std.testing.allocator, std.process.Environ.empty, &.{ "--cache", "8MiB", "4096" }, &diag);
    defer CLI.deinit(&cli, std.testing.allocator);
    try std.testing.expectEqual(@as(u128, 8 << 20), cli.cache.value());
    try std.testing.expectEqual(@as(u128, 4096), cli.path.value());

    var default_cli = try CLI.parse(std.testing.allocator, std.process.Environ.empty, &.{"4096"}, &diag);
    defer CLI.deinit(&default_cli, std.testing.allocator);
    try std.testing.expectEqual(@as(u128, 2097152), default_cli.cache.value());

    var data = try CLI.helpData(std.testing.allocator);
    defer data.deinit(std.testing.allocator);
    var rendered: ?[]const u8 = null;
    for (data.flag_groups) |group| {
        for (group.flags) |flag| {
            if (std.mem.eql(u8, flag.name, "cache")) rendered = flag.default;
        }
    }
    try std.testing.expectEqualStrings("2MiB", rendered orelse return error.TestUnexpectedResult);
}
