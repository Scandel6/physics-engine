const std = @import("std");
const cyclone = @import("physics-engine");
const assert = std.debug.assert;

pub const rl = @cImport({
    @cInclude("raylib.h");
});

const Vec3 = cyclone.core.Vector3(f32);

pub fn toRl(v: Vec3) rl.Vector3 {
    return .{ .x = v[0], .y = v[1], .z = v[2] };
}
