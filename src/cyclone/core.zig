//! Interface file for core components and functions.

const std = @import("std");
const testing = std.testing;
const math = std.math;

/// Vector3 in right-handed space.
pub fn Vector3(comptime T: type) type {
    if (@typeInfo(T) != .float) @compileError("T must be a float type");

    const epsilon: T = switch (T) {
        f32 => 1e-5,
        f64 => 1e-9,
        else => @compileError("Error: epsilon"),
    };

    return struct {
        x: T,
        y: T,
        z: T,

        pub fn init(x: T, y: T, z: T) @This() {
            return .{ .x = x, .y = y, .z = z };
        }

        pub fn zero() @This() {
            return .{ .x = 0, .y = 0, .z = 0 };
        }

        pub fn fill(s: T) @This() {
            return .{ .x = s, .y = s, .z = s };
        }

        pub fn invert(self: *@This()) void {
            self.x = -self.x;
            self.y = -self.y;
            self.z = -self.z;
        }

        test "invert" {
            var v = @This().init(0.1, 0.2, 3.0);
            v.invert();
            try testing.expect(v.eq(@This().init(-0.1, -0.2, -3.0)));
        }

        pub fn magnitude(self: @This()) T {
            return std.math.sqrt(self.squareMagnitude());
        }

        pub fn squareMagnitude(self: @This()) T {
            return self.x * self.x + self.y * self.y + self.z * self.z;
        }

        /// Turns a non-zero vector into a vector of unit length.
        pub fn normalise(self: *@This()) void {
            const m = self.magnitude();
            if (m > 0) {
                self.x /= m;
                self.y /= m;
                self.z /= m;
            }
        }

        test "normalise" {
            var v = @This().init(1.0, 1.0, 0.0);
            v.normalise();
            const expected = 1.0 / math.sqrt(2.0);
            try testing.expect(v.eq(@This().init(expected, expected, 0.0)));
        }

        /// Returns new vector scaled by n.
        pub fn mul(self: @This(), n: T) @This() {
            return @This().init(self.x * n, self.y * n, self.z * n);
        }

        pub fn mulEq(self: *@This(), n: T) void {
            self.x *= n;
            self.y *= n;
            self.z *= n;
        }

        /// Adds the given vector to this.
        pub fn addEq(self: *@This(), v: @This()) void {
            self.x += v.x;
            self.y += v.y;
            self.z += v.z;
        }

        /// Returns the value of the given vector added to this.
        pub fn add(self: @This(), v: @This()) @This() {
            return @This().init(self.x + v.x, self.y + v.y, self.z + v.z);
        }

        /// Subtracts the given vector to this.
        pub fn subEq(self: *@This(), v: @This()) void {
            self.x -= v.x;
            self.y -= v.y;
            self.z -= v.z;
        }

        /// Returns the value of the given vector subtracted from this.
        pub fn sub(self: @This(), v: @This()) @This() {
            return @This().init(self.x - v.x, self.y - v.y, self.z - v.z);
        }

        /// Calculates and returns a component-wise product of this vector
        /// with the given vector.
        pub fn componentProduct(self: @This(), v: @This()) @This() {
            return @This().init(self.x * v.x, self.y * v.y, self.z * v.z);
        }

        /// Performs a coimponent-wise product with the given vector and
        /// sets this vector to its result.
        pub fn componentProductEq(self: *@This(), v: @This()) void {
            self.x *= v.x;
            self.y *= v.y;
            self.z *= v.z;
        }

        /// Calculates and returns the scalar product of this vector
        /// with the given vector.
        pub fn dot(self: @This(), v: @This()) T {
            return self.x * v.x + self.y * v.y + self.z * v.z;
        }

        /// Calculates and returns the vector product of this vector
        /// with the given vector.
        pub fn cross(self: @This(), v: @This()) @This() {
            const x = self.y * v.z - self.z * v.y;
            const y = self.z * v.x - self.x * v.z;
            const z = self.x * v.y - self.y * v.x;
            return @This().init(x, y, z);
        }

        /// Updates this vector to be the vector product of its current
        /// value and the given vector.
        pub fn crossEq(self: *@This(), v: @This()) void {
            const x = self.y * v.z - self.z * v.y;
            const y = self.z * v.x - self.x * v.z;
            const z = self.x * v.y - self.y * v.x;

            self.x = x;
            self.y = y;
            self.z = z;
        }

        test "cross product" {
            const v1 = @This().init(1.0, 0.0, 0.0);
            const v2 = @This().init(0.0, 1.0, 0.0);
            const result = v1.cross(v2);
            try testing.expect(result.eq(@This().init(0.0, 0.0, 1.0)));

            var v3 = @This().init(1.0, 0.0, 0.0);
            v3.crossEq(@This().init(0.0, 1.0, 0.0));
            try testing.expect(v3.eq(@This().init(0.0, 0.0, 1.0)));
        }

        /// Adds to given vector another one scaled.
        pub fn addScaledVector(self: *@This(), v: @This(), scale: T) void {
            self.x += v.x * scale;
            self.y += v.y * scale;
            self.z += v.z * scale;
        }

        test "add scaled vector" {
            var v1 = @This().init(1.0, 0.0, 0.0);
            const v2 = @This().init(0.0, 1.0, 0.0);
            v1.addScaledVector(v2, 10);
            try testing.expect(v1.eq(@This().init(1.0, 10.0, 0.0)));
        }

        pub fn eq(self: @This(), v: @This()) bool {
            return math.approxEqAbs(T, self.x, v.x, epsilon) and
                math.approxEqAbs(T, self.y, v.y, epsilon) and
                math.approxEqAbs(T, self.z, v.z, epsilon);
        }

        pub fn isZero(self: *@This()) bool {
            return self.eq(@This().init(0, 0, 0));
        }
    };
}

//        pub fn orthonormalBasis(v1: @This(), v2: @This()) ?[]@This() {
//            var v = v1.cross(v2);
//            if (v.magnitude() == 0)
//                return null;
//
//            v2 = v.cross(v1);
//
//           return [v1, v2, v3];
//        }

test {
    _ = Vector3(f32);
    _ = Vector3(f64);
}

// To verify the non-float compile error, temporarily uncomment:
// test "Vector3 rejects non-float" { _ = Vector3(bool); }
