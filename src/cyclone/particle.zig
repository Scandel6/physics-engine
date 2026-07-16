//!  File for the particle functionality.
const std = @import("std");
const testing = std.testing;
const math = std.math;
const mem = std.mem;

const Allocator = mem.Allocator;

const core = @import("core.zig");

/// A particle is the simplest object that can be simulated in the
/// physics system.
pub fn Particle(comptime T: type) type {
    const Vec3 = core.Vector3(T);
    return struct {
        /// Holds the linear position of the particle in
        /// world space.
        position_x: T,
        position_y: T,
        position_z: T,

        /// Holds the linear velocity of the particle in world space.
        velocity_x: T,
        velocity_y: T,
        velocity_z: T,

        /// Holds the acceleration of the particle. This value
        /// can be used to set acceleartion due to gravity
        /// or any other constant acceleration.
        acceleration_x: T,
        acceleration_y: T,
        acceleration_z: T,

        /// Holds the accumulated force to be applied at the next
        /// simulation iteration only. This value is zeroed at each
        /// integration step.
        force_accum_x: T,
        force_accum_y: T,
        force_accum_z: T,

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
        inverse_mass: T,

        pub fn position(self: *const @This()) Vec3 {
            return .{ self.position_x, self.position_y, self.position_z, 0 };
        }

        pub fn setPosition(self: *@This(), v: Vec3) void {
            self.position_x = v[0];
            self.position_y = v[1];
            self.position_z = v[2];
        }

        pub fn velocity(self: *const @This()) Vec3 {
            return .{ self.velocity_x, self.velocity_y, self.velocity_z, 0 };
        }

        pub fn setVelocity(self: *@This(), v: Vec3) void {
            self.velocity_x = v[0];
            self.velocity_y = v[1];
            self.velocity_z = v[2];
        }

        pub fn acceleration(self: *const @This()) Vec3 {
            return .{ self.acceleration_x, self.acceleration_y, self.acceleration_z, 0 };
        }

        pub fn setAcceleration(self: *@This(), v: Vec3) void {
            self.acceleration_x = v[0];
            self.acceleration_y = v[1];
            self.acceleration_z = v[2];
        }

        pub fn forceAccum(self: *const @This()) Vec3 {
            return .{ self.force_accum_x, self.force_accum_y, self.force_accum_z, 0 };
        }

        pub fn setForceAccum(self: *@This(), v: Vec3) void {
            self.force_accum_x = v[0];
            self.force_accum_y = v[1];
            self.force_accum_z = v[2];
        }
    };
}

/// Create default particles (all 0, damping 1, inverse_mass 0 = infinite mass).
pub fn defaultParticle(comptime T: type) Particle(T) {
    return .{
        .position_x = 0,
        .position_y = 0,
        .position_z = 0,

        .velocity_x = 0,
        .velocity_y = 0,
        .velocity_z = 0,

        .acceleration_x = 0,
        .acceleration_y = 0,
        .acceleration_z = 0,

        .force_accum_x = 0,
        .force_accum_y = 0,
        .force_accum_z = 0,

        .damping = 1,

        .inverse_mass = 0,
    };
}

/// This system will handle and process all particles.
pub fn ParticleSystem(comptime T: type) type {
    const ParticleType = Particle(T);
    const v3 = core.vec3(T);
    const Vec3 = core.Vector3(T);
    const batch = core.batch(T);

    return struct {
        /// Stores all the particles in contiguous memory separated by fields.
        data: std.MultiArrayList(ParticleType),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .data = .{},
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.data.deinit(self.allocator);
        }

        test "init/deinit" {
            var system = ParticleSystem(T).init(testing.allocator);
            defer system.deinit();
        }

        /// Add a particle.
        pub fn addParticle(self: *@This(), p: ParticleType) !void {
            try self.data.append(self.allocator, p);
        }

        test "addParticle" {
            var system = ParticleSystem(T).init(testing.allocator);
            defer system.deinit();

            const p = defaultParticle(T);
            try system.addParticle(p);
            try testing.expectEqual(@as(usize, 1), system.data.len);

            try system.addParticle(p);
            try system.addParticle(p);
            try testing.expectEqual(@as(usize, 3), system.data.len);
        }

        /// Integrates the particle batch forward in time by the given amount.
        /// This function uses a Newton-Euler integration method, which
        /// is a linear approximation of the correct integral. For this
        /// reason, it may be inaccurate in some cases.
        ///
        /// TODO: Implement an optimization for inactive particles (sparse-set).
        pub fn integrateAll(self: *@This(), duration: T) !void {
            std.debug.assert(duration > 0.0);

            // Extract slices of every property
            const slice = self.data.slice();

            const positions_x = slice.items(.position_x);
            const positions_y = slice.items(.position_y);
            const positions_z = slice.items(.position_z);

            const velocities_x = slice.items(.velocity_x);
            const velocities_y = slice.items(.velocity_y);
            const velocities_z = slice.items(.velocity_z);

            const accelerations_x = slice.items(.acceleration_x);
            const accelerations_y = slice.items(.acceleration_y);
            const accelerations_z = slice.items(.acceleration_z);

            const force_accums_x = slice.items(.force_accum_x);
            const force_accums_y = slice.items(.force_accum_y);
            const force_accums_z = slice.items(.force_accum_z);

            const inverse_masses = slice.items(.inverse_mass);
            const dampings = slice.items(.damping);

            // pos += vel*dt
            batch.addScaled3(
                positions_x,
                positions_y,
                positions_z,
                velocities_x,
                velocities_y,
                velocities_z,
                duration,
            );

            // vel += (acc+force*invMass)*dt
            batch.addScaled3Fused(
                velocities_x,
                velocities_y,
                velocities_z,
                accelerations_x,
                accelerations_y,
                accelerations_z,
                force_accums_x,
                force_accums_y,
                force_accums_z,
                inverse_masses,
                duration,
            );

            // vel *= damping^dt
            batch.mul3Drag(
                velocities_x,
                velocities_y,
                velocities_z,
                dampings,
                duration,
            );

            // force_accums are zeroed by the caller via clearForceAccums()
        }

        test "integrateAll - full pipeline" {
            var system = ParticleSystem(T).init(testing.allocator);
            defer system.deinit();

            var p = defaultParticle(T);

            // Particle 1
            p.setAcceleration(v3.init(0, -10, 0));
            p.setForceAccum(v3.init(10, 0, 0));
            p.setVelocity(v3.init(1, 0, 0));
            p.inverse_mass = 0.5;
            p.damping = 0.9;

            try system.addParticle(p);

            // Particle 2 - infinite mass
            p = defaultParticle(T);
            p.setAcceleration(v3.init(0, -10, 0));
            p.setForceAccum(v3.init(100, 200, 300));
            p.damping = 0.5;
            try system.addParticle(p);

            // Particle 3
            p = defaultParticle(T);
            p.setVelocity(v3.init(2, 3, 4));
            p.setForceAccum(v3.init(1, 2, 3));
            try system.addParticle(p);

            try system.integrateAll(1.0);

            // P1: pos += vel*1 = (1,0,0), resultAcc = (0,-10,0) + (10,0,0)*0.5 = (5,-10,0)
            //     vel += resultAcc*1 = (6,-10,0), vel *= 0.9^1 = (5.4,-9,0)
            try testing.expect(v3.eq(system.position(0), v3.init(1, 0, 0)));
            try testing.expect(v3.eq(system.velocity(0), v3.init(5.4, -9, 0)));
            // P2: inverse_mass=0, force ignored. vel += acc*1 = (0,-10,0), vel *= 0.5 = (0,-5,0)
            try testing.expect(v3.eq(system.velocity(1), v3.init(0, -5, 0)));
            // P3: pos += (2,3,4)
            try testing.expect(v3.eq(system.position(2), v3.init(2, 3, 4)));

            // force_accums zeroed by clearForceAccums (not by integrateAll)
            system.clearForceAccums();
            try testing.expect(v3.isZero(system.forceAccum(2)));
        }

        test "integrateAll - empty system" {
            var system = ParticleSystem(T).init(testing.allocator);
            defer system.deinit();

            try system.integrateAll(0.5);
        }

        pub fn ensureTotalCapacity(self: *@This(), new_capacity: usize) Allocator.Error!void {
            try self.data.ensureTotalCapacity(self.allocator, new_capacity);
        }

        test "ensure total capacity" {
            var system = ParticleSystem(T).init(testing.allocator);
            defer system.deinit();
            try system.ensureTotalCapacity(20);
            try system.ensureTotalCapacity(0);
        }

        /// Adds the given force to the particle in the given index.
        pub fn addForce(self: *@This(), index: usize, force: Vec3) void {
            self.data.items(.force_accum_x)[index] += force[0];
            self.data.items(.force_accum_y)[index] += force[1];
            self.data.items(.force_accum_z)[index] += force[2];
        }

        pub fn clearForceAccums(self: *@This()) void {
            @memset(self.data.items(.force_accum_x), 0);
            @memset(self.data.items(.force_accum_y), 0);
            @memset(self.data.items(.force_accum_z), 0);
        }

        test "addForce" {
            var system = ParticleSystem(T).init(testing.allocator);
            defer system.deinit();

            var p = defaultParticle(T);

            p.setAcceleration(v3.init(0, -10, 0));
            p.setVelocity(v3.init(1, 0, 0));
            p.inverse_mass = 0.5;
            p.damping = 0.9;

            try system.addParticle(p);

            const force = v3.init(2, 3, 5);

            system.addForce(0, force);

            try testing.expect(v3.eq(system.forceAccum(0), force));
            try system.integrateAll(0.5);
            system.clearForceAccums();
            try testing.expect(v3.isZero(system.forceAccum(0)));
        }

        test "clearForceAccums" {
            var system = ParticleSystem(T).init(testing.allocator);
            defer system.deinit();

            var p = defaultParticle(T);
            p.setForceAccum(v3.init(10, 20, 30));
            try system.addParticle(p);
            p.setForceAccum(v3.init(40, 50, 60));
            try system.addParticle(p);

            system.clearForceAccums();

            try testing.expect(v3.isZero(system.forceAccum(0)));
            try testing.expect(v3.isZero(system.forceAccum(1)));
        }

        pub fn position(self: @This(), i: usize) Vec3 {
            return .{
                self.data.items(.position_x)[i],
                self.data.items(.position_y)[i],
                self.data.items(.position_z)[i],
                0,
            };
        }

        pub fn velocity(self: @This(), i: usize) Vec3 {
            return .{
                self.data.items(.velocity_x)[i],
                self.data.items(.velocity_y)[i],
                self.data.items(.velocity_z)[i],
                0,
            };
        }

        pub fn acceleration(self: @This(), i: usize) Vec3 {
            return .{
                self.data.items(.acceleration_x)[i],
                self.data.items(.acceleration_y)[i],
                self.data.items(.acceleration_z)[i],
                0,
            };
        }

        pub fn forceAccum(self: @This(), i: usize) Vec3 {
            return .{
                self.data.items(.force_accum_x)[i],
                self.data.items(.force_accum_y)[i],
                self.data.items(.force_accum_z)[i],
                0,
            };
        }
    };
}

test {
    _ = ParticleSystem(f32);
    _ = ParticleSystem(f64);
}
