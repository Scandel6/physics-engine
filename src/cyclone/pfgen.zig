//! File for the force generators.

const std = @import("std");
const particle = @import("particle.zig");
const core = @import("core.zig");
const mem = std.mem;
const testing = std.testing;

fn ParticleSlices(comptime T: type) type {
    return struct {
        positions_x: []T,
        positions_y: []T,
        positions_z: []T,

        velocities_x: []T,
        velocities_y: []T,
        velocities_z: []T,

        accelerations_x: []T,
        accelerations_y: []T,
        accelerations_z: []T,

        force_accums_x: []T,
        force_accums_y: []T,
        force_accums_z: []T,

        inverse_masses: []T,
        dampings: []T,
    };
}

/// Data struct for Gravity Force Generators.
pub fn GravityData(comptime T: type) type {
    return struct {
        particle_index: usize,
        gravity: core.Vector3(T),
    };
}

/// Data struact for Drag Force Generators.
pub fn DragData(comptime T: type) type {
    return struct {
        particle_index: usize,
        /// Holds the velocity drag coefficent.
        k1: T,
        /// Holds the velocity squared drag coefficent.
        k2: T,
    };
}

fn applyGravity(
    comptime T: type,
    slices: ParticleSlices(T),
    indices: []const usize,
    gravities: []const core.Vector3(T),
    len: usize,
) void {
    // indices are sparse for p_idx, no batch possible for now
    for (0..len) |i| {
        const p_idx = indices[i];
        const inv_mass = slices.inverse_masses[p_idx];
        if (inv_mass <= 0) continue;
        const mass = 1 / inv_mass;

        slices.force_accums_x[p_idx] += gravities[i][0] * mass;
        slices.force_accums_y[p_idx] += gravities[i][1] * mass;
        slices.force_accums_z[p_idx] += gravities[i][2] * mass;
    }
}

/// The drag equation is a simplification of two formulae, the lineal part comes from
/// Stoke's Law which mainly applies to low velocities (thus lineal). Meanwhile the
/// quadratic part comes from the Aerodynamic Drag equation.
///
/// https://en.wikipedia.org/wiki/Stokes%27s_law
/// https://en.wikipedia.org/wiki/Drag_(physics)#The_drag_equation
///
/// TODO: Investigate the derivations of these equations and see if it can be improved
fn applyDrag(
    comptime T: type,
    slices: ParticleSlices(T),
    indices: []const usize,
    k1s: []const T,
    k2s: []const T,
    len: usize,
) void {
    const v3 = core.vec3(T);
    for (0..len) |i| {
        const p_idx = indices[i];
        var force = v3.init(
            slices.velocities_x[p_idx],
            slices.velocities_y[p_idx],
            slices.velocities_z[p_idx],
        );

        var drag_coeff = v3.magnitude(force);
        drag_coeff = k1s[i] * drag_coeff + k2s[i] * drag_coeff * drag_coeff;

        force = v3.normalize(force);
        force = v3.mul(force, -drag_coeff);
        slices.force_accums_x[p_idx] += force[0];
        slices.force_accums_y[p_idx] += force[1];
        slices.force_accums_z[p_idx] += force[2];
    }
}

/// Holds all the force generators and the particles they apply to.
pub fn ParticleForceRegistry(comptime T: type) type {
    const Vec3 = core.Vector3(T);

    return struct {
        gravity: std.MultiArrayList(GravityData(T)),
        drag: std.MultiArrayList(DragData(T)),
        allocator: mem.Allocator,

        pub fn init(alloc: mem.Allocator) @This() {
            return .{
                .gravity = .{},
                .drag = .{},
                .allocator = alloc,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.gravity.deinit(self.allocator);
            self.drag.deinit(self.allocator);
        }

        test "init/deinit" {
            var registry = ParticleForceRegistry(T).init(testing.allocator);
            defer registry.deinit();
        }

        pub fn addGravity(self: *@This(), p_idx: usize, g: Vec3) mem.Allocator.Error!void {
            try self.gravity.append(self.allocator, .{ .particle_index = p_idx, .gravity = g });
        }

        pub fn addDrag(self: *@This(), p_idx: usize, k1: T, k2: T) mem.Allocator.Error!void {
            try self.drag.append(self.allocator, .{ .particle_index = p_idx, .k1 = k1, .k2 = k2 });
        }

        pub fn ensureTotalCapacity(self: *@This(), new_cap: usize) mem.Allocator.Error!void {
            try self.gravity.ensureTotalCapacity(self.allocator, new_cap);
            try self.drag.ensureTotalCapacity(self.allocator, new_cap);
        }

        test "gravity - applies force scaled by mass, skips infinite mass" {
            const v3 = core.vec3(T);
            var system = particle.ParticleSystem(T).init(testing.allocator);
            defer system.deinit();
            var registry = ParticleForceRegistry(T).init(testing.allocator);
            defer registry.deinit();

            var p = particle.defaultParticle(T);
            p.inverse_mass = 0.5; // mass = 2kg
            try system.addParticle(p);
            p.inverse_mass = 0; // infinite mass, gravity should skip
            try system.addParticle(p);
            p.inverse_mass = 1; // mass = 1kg
            try system.addParticle(p);

            const g = v3.init(0, -10, 0);
            try registry.addGravity(0, g);
            try registry.addGravity(1, g);
            try registry.addGravity(2, g);

            registry.updateForces(&system, 1.0);

            // P0: force = gravity * mass = (0,-10,0) * 2 = (0,-20,0)
            try testing.expect(v3.eq(system.forceAccum(0), v3.init(0, -20, 0)));
            // P1: infinite mass, no force
            try testing.expect(v3.eq(system.forceAccum(1), v3.zero()));
            // P2: force = (0,-10,0) * 1 = (0,-10,0)
            try testing.expect(v3.eq(system.forceAccum(2), v3.init(0, -10, 0)));
        }

        test "drag - force opposes velocity, scales with k1 and k2" {
            const v3 = core.vec3(T);
            var system = particle.ParticleSystem(T).init(testing.allocator);
            defer system.deinit();
            var registry = ParticleForceRegistry(T).init(testing.allocator);
            defer registry.deinit();

            var p = particle.defaultParticle(T);
            p.setVelocity(v3.init(10, 0, 0));
            p.inverse_mass = 1;
            try system.addParticle(p);

            try registry.addDrag(0, 0.1, 0.01);

            registry.updateForces(&system, 1.0);

            // |force| = 10, drag_coeff = 0.1*10 + 0.01*100 = 2
            // normalized = (1,0,0), force = (1,0,0) * -2 = (-2,0,0)
            try testing.expect(v3.eq(system.forceAccum(0), v3.init(-2, 0, 0)));
        }

        test "multiple generators same particle - gravity and drag accumulate" {
            const v3 = core.vec3(T);
            var system = particle.ParticleSystem(T).init(testing.allocator);
            defer system.deinit();
            var registry = ParticleForceRegistry(T).init(testing.allocator);
            defer registry.deinit();

            var p = particle.defaultParticle(T);
            p.inverse_mass = 1;
            p.setVelocity(v3.init(10, 0, 0));
            try system.addParticle(p);

            try registry.addGravity(0, v3.init(0, -10, 0));
            try registry.addDrag(0, 0.1, 0.01);

            registry.updateForces(&system, 1.0);

            // gravity: (0,-10,0) * 1 = (0,-10,0)
            // drag: (-2,0,0)
            // total: (-2,-10,0)
            try testing.expect(v3.eq(system.forceAccum(0), v3.init(-2, -10, 0)));
        }

        /// Calls all the force generators to update the forces of
        /// their corresponding particles.
        pub fn updateForces(self: *@This(), system: *particle.ParticleSystem(T), duration: T) void {
            const slice = system.data.slice();
            const slices = ParticleSlices(T){
                .positions_x = slice.items(.position_x),
                .positions_y = slice.items(.position_y),
                .positions_z = slice.items(.position_z),

                .velocities_x = slice.items(.velocity_x),
                .velocities_y = slice.items(.velocity_y),
                .velocities_z = slice.items(.velocity_z),

                .accelerations_x = slice.items(.acceleration_x),
                .accelerations_y = slice.items(.acceleration_y),
                .accelerations_z = slice.items(.acceleration_z),

                .force_accums_x = slice.items(.force_accum_x),
                .force_accums_y = slice.items(.force_accum_y),
                .force_accums_z = slice.items(.force_accum_z),

                .inverse_masses = slice.items(.inverse_mass),
                .dampings = slice.items(.damping),
            };

            // Not used for now
            _ = duration;

            const gravity_slice = self.gravity.slice();
            applyGravity(
                T,
                slices,
                gravity_slice.items(.particle_index),
                gravity_slice.items(.gravity),
                gravity_slice.len,
            );

            const drag_slice = self.drag.slice();
            applyDrag(
                T,
                slices,
                drag_slice.items(.particle_index),
                drag_slice.items(.k1),
                drag_slice.items(.k2),
                drag_slice.len,
            );
        }
    };
}

test {
    _ = ParticleForceRegistry(f32);
    _ = ParticleForceRegistry(f64);
}
