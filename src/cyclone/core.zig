//! File for core components and functions.

const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

/// Vector3 in right-handed space.
pub fn Vector3(comptime T: type) type {
    if (@typeInfo(T) != .float) @compileError("T must be a float type");

    return @Vector(4, T);
}

fn epsilon(comptime T: type) T {
    return switch (T) {
        f32 => 1e-5,
        f64 => 1e-9,
        else => @compileError("Error: epsilon"),
    };
}

/// Namespace for all Vector3 methods.
pub fn vec3(comptime T: type) type {
    return struct {
        pub fn init(x: T, y: T, z: T) Vector3(T) {
            return .{ x, y, z, 0 };
        }

        pub fn zero() Vector3(T) {
            return .{ 0, 0, 0, 0 };
        }

        pub fn fill(s: T) Vector3(T) {
            return .{ s, s, s, 0 };
        }

        pub fn magnitude(v: Vector3(T)) T {
            return @sqrt(@reduce(.Add, v * v));
        }

        pub fn squareMagnitude(v: Vector3(T)) T {
            return @reduce(.Add, v * v);
        }

        /// Returns the scalar product of given vectors.
        pub fn dot(v1: Vector3(T), v2: Vector3(T)) T {
            return @reduce(.Add, v1 * v2);
        }

        /// Returns new vector scaled by n.
        pub fn mul(v: Vector3(T), n: T) Vector3(T) {
            return v * @as(Vector3(T), @splat(n));
        }

        /// Returns the vector product of given vectors.
        pub fn cross(v1: Vector3(T), v2: Vector3(T)) Vector3(T) {
            const v1_yzx = @shuffle(T, v1, zero(), [_]i32{ 1, 2, 0, -1 });
            const v2_yzx = @shuffle(T, v2, zero(), [_]i32{ 1, 2, 0, -1 });
            const v1_zxy = @shuffle(T, v1, zero(), [_]i32{ 2, 0, 1, -1 });
            const v2_zxy = @shuffle(T, v2, zero(), [_]i32{ 2, 0, 1, -1 });

            const result = v1_yzx * v2_zxy - v1_zxy * v2_yzx;

            // Force w = 0: lanes 0-2 from result, lane 3 from @splat(0) via negative index
            return @shuffle(T, result, @as(Vector3(T), @splat(0)), [_]i32{ 0, 1, 2, -1 });
        }

        /// Returns the vector scaled to unit length.
        /// If magnitude is 0 returns 0.
        pub fn normalize(v: Vector3(T)) Vector3(T) {
            const m = magnitude(v);
            if (m > 0) return v * @as(Vector3(T), @splat(1 / m));
            return zero();
        }

        /// Checks if both vectors are equal with a slight margin (epsilon).
        pub fn eq(v1: Vector3(T), v2: Vector3(T)) bool {
            const eps = @as(Vector3(T), @splat(epsilon(T)));
            return @reduce(.And, @abs(v1 - v2) <= eps);
        }

        pub fn isZero(v: Vector3(T)) bool {
            return eq(v, zero());
        }

        test "constructors enforce w=0" {
            const vec3T = vec3(T);
            const v = vec3T.init(1.0, 2.0, 3.0);
            try testing.expectEqual(@as(T, 1.0), v[0]);
            try testing.expectEqual(@as(T, 2.0), v[1]);
            try testing.expectEqual(@as(T, 3.0), v[2]);
            try testing.expectEqual(@as(T, 0), v[3]);

            const z = vec3T.zero();
            try testing.expectEqual(@as(T, 0), z[0]);
            try testing.expectEqual(@as(T, 0), z[1]);
            try testing.expectEqual(@as(T, 0), z[2]);
            try testing.expectEqual(@as(T, 0), z[3]);

            const f = vec3T.fill(5.0);
            try testing.expectEqual(@as(T, 5.0), f[0]);
            try testing.expectEqual(@as(T, 5.0), f[1]);
            try testing.expectEqual(@as(T, 5.0), f[2]);
            try testing.expectEqual(@as(T, 0), f[3]);
        }

        test "operators preserve w=0" {
            const vec3T = vec3(T);
            const a = vec3T.init(1.0, 2.0, 3.0);
            const b = vec3T.init(4.0, 5.0, 6.0);

            try testing.expectEqual(@as(T, 0), (a + b)[3]);
            try testing.expectEqual(@as(T, 0), (a - b)[3]);
            try testing.expectEqual(@as(T, 0), (-a)[3]);
            try testing.expectEqual(@as(T, 0), (a * b)[3]);
            try testing.expectEqual(@as(T, 0), vec3T.mul(a, 2.0)[3]);
        }

        test "invert" {
            const vec3T = vec3(T);
            var v = vec3T.init(0.1, 0.2, 3.0);
            v = -v;
            try testing.expect(vec3T.eq(v, vec3T.init(-0.1, -0.2, -3.0)));
            try testing.expectEqual(@as(T, 0), v[3]);
        }

        test "normalize" {
            const vec3T = vec3(T);
            const v = vec3T.init(1.0, 1.0, 0.0);
            const v1 = vec3T.normalize(v);
            const expected: T = 1.0 / @sqrt(2.0);
            try testing.expect(vec3T.eq(v1, vec3T.init(expected, expected, 0.0)));
            try testing.expectEqual(@as(T, 0), v1[3]);
        }

        test "cross product" {
            const vec3T = vec3(T);

            const v1 = vec3T.init(1.0, 0.0, 0.0);
            const v2 = vec3T.init(0.0, 1.0, 0.0);
            const result = vec3T.cross(v1, v2);
            try testing.expect(vec3T.eq(result, vec3T.init(0.0, 0.0, 1.0)));
            try testing.expectEqual(@as(T, 0), result[3]);

            const v3 = vec3T.init(1.0, 0.0, 0.0);
            const v4 = vec3T.cross(v3, vec3T.init(0.0, 1.0, 0.0));
            try testing.expect(vec3T.eq(v4, vec3T.init(0.0, 0.0, 1.0)));
            try testing.expectEqual(@as(T, 0), v4[3]);
        }

        test "add scaled (operator + mul)" {
            const vec3T = vec3(T);

            var v1 = vec3T.init(1.0, 0.0, 0.0);
            const v2 = vec3T.init(0.0, 1.0, 0.0);
            v1 += vec3T.mul(v2, 10);
            try testing.expect(vec3T.eq(v1, vec3T.init(1.0, 10.0, 0.0)));
            try testing.expectEqual(@as(T, 0), v1[3]);
        }
    };
}

/// Namespace for all Vectorized operations
pub fn batch(comptime T: type) type {
    return struct {
        const REG_BITS: usize = blk: {
            const cpu = builtin.cpu;
            if (cpu.arch == .x86_64 and std.Target.x86.featureSetHas(cpu.features, .avx2))
                break :blk 256;
            break :blk 128;
        };
        const WIDTH: usize = REG_BITS / @bitSizeOf(T);
        const V = @Vector(WIDTH, T);

        /// pos[i] += vel[i] * dt (dt constant)
        pub fn addScaled3(
            pos_x: []T,
            pos_y: []T,
            pos_z: []T,
            vel_x: []const T,
            vel_y: []const T,
            vel_z: []const T,
            dt: T,
        ) void {
            const len = pos_x.len;
            const sv = @as(V, @splat(dt));
            var i: usize = 0;

            // *WIDTH* elements by iteration
            while (i + WIDTH <= len) : (i += WIDTH) {
                // LOAD: slice[i..][0..WIDTH] → ptr to 4 elems → @as(V, .* ) loads as vector
                var dx = @as(V, pos_x[i..][0..WIDTH].*);
                var dy = @as(V, pos_y[i..][0..WIDTH].*);
                var dz = @as(V, pos_z[i..][0..WIDTH].*);
                const sx = @as(V, vel_x[i..][0..WIDTH].*);
                const sy = @as(V, vel_y[i..][0..WIDTH].*);
                const sz = @as(V, vel_z[i..][0..WIDTH].*);

                // COMPUTE: 1 mulps + 1 addps per compoment (3 of each in total)
                dx += sx * sv;
                dy += sy * sv;
                dz += sz * sv;

                // STORE: @as([WIDTH]T, vec) converts the vector into an array → .* dereferences
                pos_x[i..][0..WIDTH].* = @as([WIDTH]T, dx);
                pos_y[i..][0..WIDTH].* = @as([WIDTH]T, dy);
                pos_z[i..][0..WIDTH].* = @as([WIDTH]T, dz);
            }

            // Remainder: len % WIDTH elements, scalar
            while (i < len) : (i += 1) {
                pos_x[i] += vel_x[i] * dt;
                pos_y[i] += vel_y[i] * dt;
                pos_z[i] += vel_z[i] * dt;
            }
        }

        /// vel[i] += (acc + force * inv_mass) * dt
        pub fn addScaled3Fused(
            vel_x: []T,
            vel_y: []T,
            vel_z: []T,
            acc_x: []const T,
            acc_y: []const T,
            acc_z: []const T,
            force_x: []const T,
            force_y: []const T,
            force_z: []const T,
            inv_mass: []const T,
            dt: T,
        ) void {
            const len = vel_x.len;
            const sv = @as(V, @splat(dt));
            var i: usize = 0;

            while (i + WIDTH <= len) : (i += WIDTH) {
                var dx = @as(V, vel_x[i..][0..WIDTH].*);
                var dy = @as(V, vel_y[i..][0..WIDTH].*);
                var dz = @as(V, vel_z[i..][0..WIDTH].*);

                const ax = @as(V, acc_x[i..][0..WIDTH].*);
                const ay = @as(V, acc_y[i..][0..WIDTH].*);
                const az = @as(V, acc_z[i..][0..WIDTH].*);

                const fx = @as(V, force_x[i..][0..WIDTH].*);
                const fy = @as(V, force_y[i..][0..WIDTH].*);
                const fz = @as(V, force_z[i..][0..WIDTH].*);

                const im = @as(V, inv_mass[i..][0..WIDTH].*);

                dx += (ax + fx * im) * sv;
                dy += (ay + fy * im) * sv;
                dz += (az + fz * im) * sv;

                vel_x[i..][0..WIDTH].* = @as([WIDTH]T, dx);
                vel_y[i..][0..WIDTH].* = @as([WIDTH]T, dy);
                vel_z[i..][0..WIDTH].* = @as([WIDTH]T, dz);
            }

            while (i < len) : (i += 1) {
                vel_x[i] += (acc_x[i] + force_x[i] * inv_mass[i]) * dt;
                vel_y[i] += (acc_y[i] + force_y[i] * inv_mass[i]) * dt;
                vel_z[i] += (acc_z[i] + force_z[i] * inv_mass[i]) * dt;
            }
        }

        /// vel[i] *= damping[i] ^ dt
        pub fn mul3Drag(
            vel_x: []T,
            vel_y: []T,
            vel_z: []T,
            dampings: []const T,
            dt: T,
        ) void {
            const len = vel_x.len;
            const sv = @as(V, @splat(dt));
            var i: usize = 0;

            while (i + WIDTH <= len) : (i += WIDTH) {
                var dx = @as(V, vel_x[i..][0..WIDTH].*);
                var dy = @as(V, vel_y[i..][0..WIDTH].*);
                var dz = @as(V, vel_z[i..][0..WIDTH].*);
                const srcv = @as(V, dampings[i..][0..WIDTH].*);

                const res = @exp(sv * @log(srcv));

                dx *= res;
                dy *= res;
                dz *= res;

                vel_x[i..][0..WIDTH].* = @as([WIDTH]T, dx);
                vel_y[i..][0..WIDTH].* = @as([WIDTH]T, dy);
                vel_z[i..][0..WIDTH].* = @as([WIDTH]T, dz);
            }

            while (i < len) : (i += 1) {
                const res = @exp(dt * @log(dampings[i]));
                vel_x[i] *= res;
                vel_y[i] *= res;
                vel_z[i] *= res;
            }
        }

        pub fn zero3(x: []T, y: []T, z: []T) void {
            @memset(x, 0);
            @memset(y, 0);
            @memset(z, 0);
        }

        test "addScaled3 - boundary lengths" {
            const lens = [_]usize{ 0, 1, 3, 4, 5, 8 };
            var pos_x: [8]T = undefined;
            var pos_y: [8]T = undefined;
            var pos_z: [8]T = undefined;
            var vel_x: [8]T = undefined;
            var vel_y: [8]T = undefined;
            var vel_z: [8]T = undefined;

            const eps = epsilon(T);

            for (lens) |len| {
                for (0..len) |i| {
                    const fi: T = @floatFromInt(i);
                    const fi1: T = @floatFromInt(i + 1);
                    pos_x[i] = fi1;
                    pos_y[i] = fi1;
                    pos_z[i] = fi1;
                    vel_x[i] = fi * 10;
                    vel_y[i] = fi * 10;
                    vel_z[i] = fi * 10;
                }

                const dt: T = 2;
                addScaled3(
                    pos_x[0..len],
                    pos_y[0..len],
                    pos_z[0..len],
                    vel_x[0..len],
                    vel_y[0..len],
                    vel_z[0..len],
                    dt,
                );

                for (0..len) |i| {
                    const fi: T = @floatFromInt(i);
                    const fi1: T = @floatFromInt(i + 1);
                    const expected = fi1 + fi * 10 * dt;
                    try testing.expectApproxEqAbs(expected, pos_x[i], eps);
                    try testing.expectApproxEqAbs(expected, pos_y[i], eps);
                    try testing.expectApproxEqAbs(expected, pos_z[i], eps);
                }
            }
        }

        test "addScaled3Fused - boundary lengths" {
            const lens = [_]usize{ 0, 1, 3, 4, 5, 8 };
            var vel_x: [8]T = undefined;
            var vel_y: [8]T = undefined;
            var vel_z: [8]T = undefined;
            var acc_x: [8]T = undefined;
            var acc_y: [8]T = undefined;
            var acc_z: [8]T = undefined;
            var force_x: [8]T = undefined;
            var force_y: [8]T = undefined;
            var force_z: [8]T = undefined;
            var inv_mass: [8]T = undefined;

            const eps = epsilon(T);

            for (lens) |len| {
                for (0..len) |i| {
                    const fi1: T = @floatFromInt(i + 1);
                    vel_x[i] = 1;
                    vel_y[i] = 1;
                    vel_z[i] = 1;
                    acc_x[i] = 0;
                    acc_y[i] = 0;
                    acc_z[i] = 0;
                    force_x[i] = fi1 * 10;
                    force_y[i] = fi1 * 10;
                    force_z[i] = fi1 * 10;
                    inv_mass[i] = 0.5;
                }

                const dt: T = 2;
                addScaled3Fused(
                    vel_x[0..len],
                    vel_y[0..len],
                    vel_z[0..len],
                    acc_x[0..len],
                    acc_y[0..len],
                    acc_z[0..len],
                    force_x[0..len],
                    force_y[0..len],
                    force_z[0..len],
                    inv_mass[0..len],
                    dt,
                );

                for (0..len) |i| {
                    const fi1: T = @floatFromInt(i + 1);
                    // vel = 1 + (0 + (i+1)*10 * 0.5) * 2 = 1 + (i+1)*10
                    const expected: T = 1 + fi1 * 10;
                    try testing.expectApproxEqAbs(expected, vel_x[i], eps);
                    try testing.expectApproxEqAbs(expected, vel_y[i], eps);
                    try testing.expectApproxEqAbs(expected, vel_z[i], eps);
                }
            }
        }

        test "addScaled3Fused - infinite mass (inv_mass=0)" {
            var vel_x: [4]T = .{ 1, 2, 3, 4 };
            var vel_y: [4]T = .{ 1, 2, 3, 4 };
            var vel_z: [4]T = .{ 1, 2, 3, 4 };
            const acc_x: [4]T = .{ 10, 20, 30, 40 };
            const acc_y: [4]T = .{ 10, 20, 30, 40 };
            const acc_z: [4]T = .{ 10, 20, 30, 40 };
            const force_x: [4]T = .{ 100, 200, 300, 400 };
            const force_y: [4]T = .{ 100, 200, 300, 400 };
            const force_z: [4]T = .{ 100, 200, 300, 400 };
            const inv_mass: [4]T = .{ 0, 0, 0, 0 };
            const dt: T = 2;

            const eps = epsilon(T);

            addScaled3Fused(
                vel_x[0..],
                vel_y[0..],
                vel_z[0..],
                acc_x[0..],
                acc_y[0..],
                acc_z[0..],
                force_x[0..],
                force_y[0..],
                force_z[0..],
                inv_mass[0..],
                dt,
            );

            // inv_mass=0 → force*0=0 → vel += acc*dt only
            for (0..4) |i| {
                const fbase: T = @floatFromInt(i + 1);
                const facc: T = @floatFromInt((i + 1) * 10);
                const expected = fbase + facc * dt;
                try testing.expectApproxEqAbs(expected, vel_x[i], eps);
                try testing.expectApproxEqAbs(expected, vel_y[i], eps);
                try testing.expectApproxEqAbs(expected, vel_z[i], eps);
            }
        }

        test "mul3Drag - damping 1 (no change)" {
            const lens = [_]usize{ 0, 1, 3, 4, 5, 8 };
            var vel_x: [8]T = undefined;
            var vel_y: [8]T = undefined;
            var vel_z: [8]T = undefined;
            var dampings: [8]T = undefined;

            const eps = epsilon(T);

            for (lens) |len| {
                for (0..len) |i| {
                    const fi: T = @floatFromInt(i + 1);
                    vel_x[i] = fi;
                    vel_y[i] = fi;
                    vel_z[i] = fi;
                    dampings[i] = 1;
                }

                mul3Drag(vel_x[0..len], vel_y[0..len], vel_z[0..len], dampings[0..len], 1);

                for (0..len) |i| {
                    const fi: T = @floatFromInt(i + 1);
                    try testing.expectApproxEqAbs(fi, vel_x[i], eps);
                    try testing.expectApproxEqAbs(fi, vel_y[i], eps);
                    try testing.expectApproxEqAbs(fi, vel_z[i], eps);
                }
            }
        }

        test "mul3Drag - damping 0.5 dt 2" {
            var vel_x: [4]T = .{ 10, 20, 30, 40 };
            var vel_y: [4]T = .{ 10, 20, 30, 40 };
            var vel_z: [4]T = .{ 10, 20, 30, 40 };
            const dampings: [4]T = .{ 0.5, 0.5, 0.5, 0.5 };

            const eps = epsilon(T);

            mul3Drag(vel_x[0..], vel_y[0..], vel_z[0..], dampings[0..], 2);

            // 0.5^2 = 0.25
            for (0..4) |i| {
                const fi: T = @floatFromInt((i + 1) * 10);
                const expected = fi * 0.25;
                try testing.expectApproxEqAbs(expected, vel_x[i], eps);
                try testing.expectApproxEqAbs(expected, vel_y[i], eps);
                try testing.expectApproxEqAbs(expected, vel_z[i], eps);
            }
        }

        test "mul3Drag - damping 0 (no NaN)" {
            var vel_x: [4]T = .{ 10, 20, 30, 40 };
            var vel_y: [4]T = .{ 10, 20, 30, 40 };
            var vel_z: [4]T = .{ 10, 20, 30, 40 };
            const dampings: [4]T = .{ 0, 0, 0, 0 };

            const eps = epsilon(T);

            mul3Drag(vel_x[0..], vel_y[0..], vel_z[0..], dampings[0..], 1);

            // 0^1 = 0 → vel = 0
            for (0..4) |i| {
                try testing.expectApproxEqAbs(@as(T, 0), vel_x[i], eps);
                try testing.expectApproxEqAbs(@as(T, 0), vel_y[i], eps);
                try testing.expectApproxEqAbs(@as(T, 0), vel_z[i], eps);
            }
        }

        test "zero3 - boundary lengths" {
            const lens = [_]usize{ 0, 1, 3, 4, 5, 8 };
            var x: [8]T = undefined;
            var y: [8]T = undefined;
            var z: [8]T = undefined;

            for (lens) |len| {
                for (0..len) |i| {
                    const fi: T = @floatFromInt(i + 1);
                    x[i] = fi;
                    y[i] = fi;
                    z[i] = fi;
                }

                zero3(x[0..len], y[0..len], z[0..len]);

                for (0..len) |i| {
                    try testing.expectEqual(@as(T, 0), x[i]);
                    try testing.expectEqual(@as(T, 0), y[i]);
                    try testing.expectEqual(@as(T, 0), z[i]);
                }
            }
        }
    };
}

test {
    _ = vec3(f32);
    _ = vec3(f64);
    _ = batch(f32);
    _ = batch(f64);
}

// To verify the non-float compile error, temporarily uncomment:
// test "Vector3 rejects non-float" { _ = Vector3(bool); }
