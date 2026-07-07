const std = @import("std");
const print = std.debug.print;
const testing = std.testing;
const math = std.math;

const core = @import("core.zig");

/// A particle is the simplest object that can be simulated in the
/// physics system
pub fn Particle(comptime T: type) type {
    const Vec3 = core.Vector3(T);
    return struct {
        /// Holds the linear position of the particle in
        /// world space
        position: Vec3,

        /// Holds the linear velocity of the particle in world space
        velocity: Vec3,

        /// Holds the acceleration of the particle. This value
        /// can be used to set acceleartion due to gravity
        /// or any other constant acceleration
        acceleration: Vec3,

        /// Holds the amount of damping applied to linear motion.
        /// Damping is required to remove energy added through
        /// numerical instability in the integrator
        // A value of 1 means that the object keeps all its velocity
        // A value of 0 means the velocity will be reduced to nothing
        // and the object could not sustain any motion
        damping: T,

        /// Holds the inverse of the mass of the particle. It is
        /// more useful to hold the inverse mass because integration
        /// is simpler and because in real-time simulation it is more
        /// useful to have objects with infinite mass than zero mass
        inverseMass: T,

        /// Holds the accumulated force to be applied at the next
        /// simulation iteration only. This value is zeroed at each
        /// integration step.
        forceAccum: Vec3,

        /// Integrates the particle forward in time by the given amount.
        /// This function uses a Newton-Euler integration method, which
        /// is a linear approximation of the correct integral. For this
        /// reason, it may be inaccurate in some cases.
        pub fn integrate(self: *@This(), duration: T) void {
            std.debug.assert(duration > 0);

            // Update linear position
            self.position.addScaledVector(self.velocity, duration);

            // Work out acceleration from the force
            var resultAcc = self.acceleration;
            resultAcc.addScaledVector(self.forceAccum, self.inverseMass);

            // Update linear velocity from acceleration
            self.velocity.addScaledVector(resultAcc, duration);

            // Impose drag
            self.velocity.mulEq(math.pow(T, self.damping, duration));

            // Zero accumulated force for next iteration
            self.forceAccum = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
        }
    };
}
