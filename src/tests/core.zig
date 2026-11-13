const std = @import("std");
const zunit = @import("../root.zig");
const core = @import("../unit/core.zig");
const volume = @import("../unit/volume.zig");
const duration = @import("../unit/duration.zig");

test "engine: scan and exact decimal arithmetic" {
    const component = try core.scanComponent("2.5", 0);
    try std.testing.expectEqual(@as(u128, 25), component.mantissa);
    try std.testing.expectEqual(@as(u32, 1), component.scale);
    try std.testing.expectEqual(@as(usize, 3), component.end);

    try std.testing.expectEqual(
        @as(u128, 2097152),
        try core.scaleToInteger(2, 0, volume.factor(.mib)),
    );
    try std.testing.expectEqual(
        @as(u128, 1572864),
        try core.scaleToInteger(15, 1, volume.factor(.mib)),
    );
    try std.testing.expectError(error.Inexact, core.scaleToInteger(1, 4, volume.factor(.mib)));
    try std.testing.expectError(error.Inexact, core.scaleToInteger(5, 1, duration.factor(.nanosecs)));
}

test "engine: every volume base is a binary shift" {
    const bases = [_]volume.VolumeBase{ .b, .kib, .mib, .gib, .tib, .pib, .eib, .zib, .yib };
    const shifts = [_]u7{ 0, 10, 20, 30, 40, 50, 60, 70, 80 };
    for (bases, shifts) |base, shift| {
        try std.testing.expectEqual(@as(u128, 1) << shift, volume.factor(base));
    }
}

test "engine: every duration base factor" {
    try std.testing.expectEqual(@as(u128, 1), duration.factor(.nanosecs));
    try std.testing.expectEqual(@as(u128, 1_000), duration.factor(.microsecs));
    try std.testing.expectEqual(@as(u128, 1_000_000), duration.factor(.millisecs));
    try std.testing.expectEqual(@as(u128, 1_000_000_000), duration.factor(.secs));
    try std.testing.expectEqual(@as(u128, 60_000_000_000), duration.factor(.mins));
    try std.testing.expectEqual(@as(u128, 3_600_000_000_000), duration.factor(.hours));
}

test "engine: volume parse sees the same grammar" {
    try std.testing.expectEqual(@as(u128, 2097152), try volume.parse(.b, "2MiB"));
    try std.testing.expectEqual(@as(u128, 2048), try volume.parse(.kib, "2KiB"));
    try std.testing.expectError(error.NotMultiple, volume.parse(.mib, "512KiB"));
    try std.testing.expectError(error.InvalidWire, volume.parse(.b, "2MB"));
}

test "engine: duration parse sees the same grammar" {
    try std.testing.expectEqual(@as(i64, 5_400_000_000_000), try duration.parse(.secs, "1h30m"));
    try std.testing.expectError(error.NotMultiple, duration.parse(.mins, "90s"));
    try std.testing.expectError(error.InvalidWire, duration.parse(.secs, "1h30"));
}

test "root: exactly the public factories and base enums" {
    try std.testing.expect(@hasDecl(zunit, "Volume"));
    try std.testing.expect(@hasDecl(zunit, "Duration"));
    try std.testing.expect(@hasDecl(zunit, "VolumeBase"));
    try std.testing.expect(@hasDecl(zunit, "DurationBase"));
}

test "root: wrapper value surfaces" {
    try std.testing.expect(@hasDecl(zunit.Volume(.b).Dap, "value64"));
    try std.testing.expect(@hasDecl(zunit.Volume(.b).Siggy, "value64"));
    try std.testing.expect(@hasDecl(zunit.Volume(.b).Dap, "deinit"));
    try std.testing.expect(!@hasDecl(zunit.Volume(.b).Siggy, "deinit"));

    try std.testing.expect(!@hasDecl(zunit.Duration(.secs).Dap, "value64"));
    try std.testing.expect(!@hasDecl(zunit.Duration(.secs).Siggy, "value64"));
    try std.testing.expect(@hasDecl(zunit.Duration(.secs).Dap, "deinit"));
    try std.testing.expect(!@hasDecl(zunit.Duration(.secs).Siggy, "deinit"));
}
