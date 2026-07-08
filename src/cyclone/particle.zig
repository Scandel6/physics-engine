const std = @import("std");
const print = std.debug.print;
const testing = std.testing;
const math = std.math;

const core = @import("core.zig");

/// A particle is the simplest object that can be simulated in the
/// physics system.
pub fn Particle(comptime T: type) type {
    const Vec3 = core.Vector3(T);
    return struct {
        /// Holds the linear position of the particle in
        /// world space.
        position: Vec3,

        /// Holds the linear velocity of the particle in world space.
        velocity: Vec3,

        /// Holds the acceleration of the particle. This value
        /// can be used to set acceleartion due to gravity
        /// or any other constant acceleration.
        acceleration: Vec3,

        /// Holds the accumulated force to be applied at the next
        /// simulation iteration only. This value is zeroed at each
        /// integration step.
        forceAccum: Vec3,

        /// Holds the amount of damping applied to linear motion.
        /// Damping is required to remove energy added through
        /// numerical instability in the integrator
        // A value of 1 means that the object keeps all its velocity
        // A value of 0 means the velocity will be reduced to nothing
        // and the object could not sustain any motion.
        damping: T,

        /// Holds the inverse of the mass of the particle. It is
        /// more useful to hold the inverse mass because integration
        /// is simpler and because in real-time simulation it is more
        /// useful to have objects with infinite mass than zero mass.
        inverseMass: T,
    };
}

/// Create default particles (all 0, damping 1).
fn makeParticle(comptime T: type) Particle(T) {
    const Vec3 = core.Vector3(T);
    return .{
        .position = Vec3.zero(),
        .velocity = Vec3.zero(),
        .acceleration = Vec3.zero(),
        .forceAccum = Vec3.zero(),
        .damping = 1,
        .inverseMass = 0,
    };
}

/// This system will handle and process all particles.
pub fn ParticleSystem(comptime T: type) type {
    const ParticleType = Particle(T);
    const Vec3 = core.Vector3(T);

    return struct {
        /// Stores all the particles in contiguous memory separated by fields.
        data: std.MultiArrayList(ParticleType),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .data = std.MultiArrayList(ParticleType){},
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.data.deinit(self.allocator);
        }

        /// Add a particle.
        pub fn addParticle(self: *@This(), p: ParticleType) !void {
            try self.data.append(self.allocator, p);
        }

        /// Integrates the particle batch forward in time by the given amount.
        /// This function uses a Newton-Euler integration method, which
        /// is a linear approximation of the correct integral. For this
        /// reason, it may be inaccurate in some cases.
        pub fn integrateAll(self: *@This(), duration: T) !void {
            std.debug.assert(duration > 0.0);

            // Extract slices of every property
            // const positions = self.data.items(.position);
            // const velocities = self.data.items(.velocity);
            // ...

            const slice = self.data.slice();

            // Iterate through every data
            for (0..self.data.len) |i| {

                // Update linear position
                slice.items(.position)[i].addScaledVector(slice.items(.velocity)[i], duration);

                // Work out acceleration from the force
                var resultAcc = slice.items(.acceleration)[i];
                resultAcc.addScaledVector(slice.items(.forceAccum)[i], slice.items(.inverseMass)[i]);

                // Update linear velocity from acceleration
                slice.items(.velocity)[i].addScaledVector(resultAcc, duration);

                // Impose drag
                slice.items(.velocity)[i].mulEq(math.pow(T, slice.items(.damping)[i], duration));

                // Zero next frame accumulated force
                slice.items(.forceAccum)[i] = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
            }
        }

        test "init/deinit" {
            var system = ParticleSystem(T).init(testing.allocator);
            defer system.deinit();
        }

        test "addParticle" {
            var system = ParticleSystem(T).init(testing.allocator);
            defer system.deinit();

            const p = makeParticle(T);
            try system.addParticle(p);
            try testing.expectEqual(@as(usize, 1), system.data.len);

            try system.addParticle(p);
            try system.addParticle(p);
            try testing.expectEqual(@as(usize, 3), system.data.len);
        }

        test "integrateAll - full pipeline" {
            var system = ParticleSystem(T).init(testing.allocator);
            defer system.deinit();

            var p = makeParticle(T);

            // Particle 1
            p.acceleration = Vec3.init(0, -10, 0);
            p.forceAccum = Vec3.init(10, 0, 0);
            p.velocity = Vec3.init(1, 0, 0);
            p.inverseMass = 0.5;
            p.damping = 0.9;

            try system.addParticle(p);

            // Particle 2 - infinite mass
            p = makeParticle(T);
            p.acceleration = Vec3.init(0, -10, 0);
            p.forceAccum = Vec3.init(100, 200, 300);
            p.damping = 0.5;
            try system.addParticle(p);

            // Particle 3
            p = makeParticle(T);
            p.velocity = Vec3.init(2, 3, 4);
            p.forceAccum = Vec3.init(1, 2, 3);
            try system.addParticle(p);

            try system.integrateAll(1.0);

            // P1: pos += vel*1 = (1,0,0), resultAcc = (0,-10,0) + (10,0,0)*0.5 = (5,-10,0)
            //     vel += resultAcc*1 = (6,-10,0), vel *= 0.9^1 = (5.4,-9,0)
            try testing.expect(system.data.items(.position)[0].eq(Vec3.init(1, 0, 0)));
            try testing.expect(system.data.items(.velocity)[0].eq(Vec3.init(5.4, -9, 0)));
            // P2: inverseMass=0, force ignored. vel += acc*1 = (0,-10,0), vel *= 0.5 = (0,-5,0)
            try testing.expect(system.data.items(.velocity)[1].eq(Vec3.init(0, -5, 0)));
            // P3: pos += (2,3,4), forces cleared
            try testing.expect(system.data.items(.position)[2].eq(Vec3.init(2, 3, 4)));
            try testing.expect(system.data.items(.forceAccum)[2].eq(Vec3.zero()));
        }

        test "integrateAll - empty system" {
            var system = ParticleSystem(T).init(testing.allocator);
            defer system.deinit();

            try system.integrateAll(0.5);
        }
    };
}

test {
    _ = ParticleSystem(f32);
    _ = ParticleSystem(f64);
}
