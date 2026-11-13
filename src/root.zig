const volume = @import("unit/volume.zig");
const duration = @import("unit/duration.zig");

pub const VolumeBase = volume.VolumeBase;

pub const DurationBase = duration.DurationBase;

pub fn Volume(comptime base: VolumeBase) type {
    return volume.Namespace(base);
}

pub fn Duration(comptime base: DurationBase) type {
    return duration.Namespace(base);
}
