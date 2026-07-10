const std = @import("std");
const cyclone = @import("physics-engine");
const assert = std.debug.assert;

pub const rl = @cImport({
    @cInclude("raylib.h");
});

const Vec3 = cyclone.Vector3(f32);

comptime {
    assert(@sizeOf(Vec3) == @sizeOf(rl.Vector3));
    assert(@offsetOf(Vec3, "x") == @offsetOf(rl.Vector3, "x"));
    assert(@offsetOf(Vec3, "y") == @offsetOf(rl.Vector3, "y"));
    assert(@offsetOf(Vec3, "z") == @offsetOf(rl.Vector3, "z"));
}

pub fn toRl(v: Vec3) rl.Vector3 {
    return .{ .x = v.x, .y = v.y, .z = v.z };
}
