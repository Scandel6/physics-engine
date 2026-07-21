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

/// Data struact for Spring Force Generators.
pub fn SpringData(comptime T: type) type {
    return struct {
        particle_index: usize,
        /// Particle at the other end of the spring.
        other_particle_index: usize,
        /// Spring constant.
        k: T,
        /// Spring rest length.
        l: T,
    };
}

/// Data struact for Anchored Spring Force Generators.
pub fn AnchoredSpringData(comptime T: type) type {
    return struct {
        particle_index: usize,
        anchor_position_x: T,
        anchor_position_y: T,
        anchor_position_z: T,
        /// Spring constant.
        k: T,
        /// Spring rest length.
        l: T,
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

fn applySpring(
    comptime T: type,
    slices: ParticleSlices(T),
    indices: []const usize,
    other_particle_indices: []const usize,
    ks: []const T,
    ls: []const T,
    len: usize,
) void {
    const v3 = core.vec3(T);
    for (0..len) |i| {
        const p_idx = indices[i];
        const o_idx = other_particle_indices[i];

        // Calculate the vector of the spring.
        var force = v3.init(
            slices.positions_x[p_idx],
            slices.positions_y[p_idx],
            slices.positions_z[p_idx],
        );

        force -= v3.init(
            slices.positions_x[o_idx],
            slices.positions_y[o_idx],
            slices.positions_z[o_idx],
        );

        // Calculate the magnitude of the force.
        var magnitude = v3.magnitude(force);

        // Hooke's law: F = -k(d - l). The book (§6.2.1) uses real_abs here,
        // which makes the spring always attract even when compressed.
        // We drop abs for physical correctness, matching AnchoredSpring.
        // Bungee will handle the "only pull when extended" case with an early return.
        magnitude = (magnitude - ls[i]) * ks[i];

        // Calculate final force.
        var norm_force = v3.normalize(force);
        norm_force = v3.mul(norm_force, -magnitude);

        slices.force_accums_x[p_idx] += norm_force[0];
        slices.force_accums_y[p_idx] += norm_force[1];
        slices.force_accums_z[p_idx] += norm_force[2];
    }
}

fn applyAnchoredSpring(
    comptime T: type,
    slices: ParticleSlices(T),
    indices: []const usize,
    anchor_position_x: []const T,
    anchor_position_y: []const T,
    anchor_position_z: []const T,
    ks: []const T,
    ls: []const T,
    len: usize,
) void {
    const v3 = core.vec3(T);
    for (0..len) |i| {
        const p_idx = indices[i];
        // Calculate the vector of the spring.
        var force = v3.init(
            slices.positions_x[p_idx],
            slices.positions_y[p_idx],
            slices.positions_z[p_idx],
        );

        force -= v3.init(
            anchor_position_x[i],
            anchor_position_y[i],
            anchor_position_z[i],
        );

        // Calculate the magnitude of the force.
        var magnitude = v3.magnitude(force);
        magnitude = (magnitude - ls[i]) * ks[i];

        // Calculate final force.
        var norm_force = v3.normalize(force);
        norm_force = v3.mul(norm_force, -magnitude);

        slices.force_accums_x[p_idx] += norm_force[0];
        slices.force_accums_y[p_idx] += norm_force[1];
        slices.force_accums_z[p_idx] += norm_force[2];
    }
}

/// Holds all the force generators and the particles they apply to.
pub fn ParticleForceRegistry(comptime T: type) type {
    const Vec3 = core.Vector3(T);

    return struct {
        gravity: std.MultiArrayList(GravityData(T)),
        drag: std.MultiArrayList(DragData(T)),
        spring: std.MultiArrayList(SpringData(T)),
        anchored_spring: std.MultiArrayList(AnchoredSpringData(T)),
        allocator: mem.Allocator,

        pub fn init(alloc: mem.Allocator) @This() {
            return .{
                .gravity = .{},
                .drag = .{},
                .spring = .{},
                .anchored_spring = .{},
                .allocator = alloc,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.gravity.deinit(self.allocator);
            self.drag.deinit(self.allocator);
            self.spring.deinit(self.allocator);
            self.anchored_spring.deinit(self.allocator);
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

        pub fn addSpring(self: *@This(), p_idx: usize, o_idx: usize, k: T, l: T) mem.Allocator.Error!void {
            try self.spring.append(self.allocator, .{
                .particle_index = p_idx,
                .other_particle_index = o_idx,
                .k = k,
                .l = l,
            });
        }

        pub fn addAnchoredSpring(
            self: *@This(),
            p_idx: usize,
            anchor_x: T,
            anchor_y: T,
            anchor_z: T,
            k: T,
            l: T,
        ) mem.Allocator.Error!void {
            try self.anchored_spring.append(self.allocator, .{
                .particle_index = p_idx,
                .anchor_position_x = anchor_x,
                .anchor_position_y = anchor_y,
                .anchor_position_z = anchor_z,
                .k = k,
                .l = l,
            });
        }

        pub fn ensureTotalCapacity(self: *@This(), new_cap: usize) mem.Allocator.Error!void {
            try self.gravity.ensureTotalCapacity(self.allocator, new_cap);
            try self.drag.ensureTotalCapacity(self.allocator, new_cap);
            try self.spring.ensureTotalCapacity(self.allocator, new_cap);
            try self.anchored_spring.ensureTotalCapacity(self.allocator, new_cap);
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

        test "spring - stretched pulls toward other particle" {
            const v3 = core.vec3(T);
            var system = particle.ParticleSystem(T).init(testing.allocator);
            defer system.deinit();
            var registry = ParticleForceRegistry(T).init(testing.allocator);
            defer registry.deinit();

            var p = particle.defaultParticle(T);
            p.inverse_mass = 1;
            p.setPosition(v3.init(3, 0, 0)); // p0 at (3,0,0)
            try system.addParticle(p);
            p.setPosition(v3.init(0, 0, 0)); // p1 at origin
            try system.addParticle(p);

            try registry.addSpring(0, 1, 1, 1); // k=1, l=1

            registry.updateForces(&system, 1.0);

            // d=3, l=1, F = -(3-1)*1 = -2 in x → (-2,0,0) toward p1
            try testing.expect(v3.eq(system.forceAccum(0), v3.init(-2, 0, 0)));
        }

        test "spring - compressed pushes away from other particle" {
            const v3 = core.vec3(T);
            var system = particle.ParticleSystem(T).init(testing.allocator);
            defer system.deinit();
            var registry = ParticleForceRegistry(T).init(testing.allocator);
            defer registry.deinit();

            var p = particle.defaultParticle(T);
            p.inverse_mass = 1;
            p.setPosition(v3.init(0.5, 0, 0)); // p0 at (0.5,0,0)
            try system.addParticle(p);
            p.setPosition(v3.init(0, 0, 0)); // p1 at origin
            try system.addParticle(p);

            try registry.addSpring(0, 1, 1, 1); // k=1, l=1

            registry.updateForces(&system, 1.0);

            // d=0.5, l=1, F = -(0.5-1)*1 = +0.5 in x → (0.5,0,0) away from p1
            try testing.expect(v3.eq(system.forceAccum(0), v3.init(0.5, 0, 0)));
        }

        test "spring - at rest length applies no force" {
            const v3 = core.vec3(T);
            var system = particle.ParticleSystem(T).init(testing.allocator);
            defer system.deinit();
            var registry = ParticleForceRegistry(T).init(testing.allocator);
            defer registry.deinit();

            var p = particle.defaultParticle(T);
            p.inverse_mass = 1;
            p.setPosition(v3.init(1, 0, 0)); // p0 at (1,0,0)
            try system.addParticle(p);
            p.setPosition(v3.init(0, 0, 0)); // p1 at origin
            try system.addParticle(p);

            try registry.addSpring(0, 1, 1, 1); // k=1, l=1

            registry.updateForces(&system, 1.0);

            // d=1=l → F=0
            try testing.expect(v3.eq(system.forceAccum(0), v3.zero()));
        }

        test "spring - only affects registered particle, not the other" {
            const v3 = core.vec3(T);
            var system = particle.ParticleSystem(T).init(testing.allocator);
            defer system.deinit();
            var registry = ParticleForceRegistry(T).init(testing.allocator);
            defer registry.deinit();

            var p = particle.defaultParticle(T);
            p.inverse_mass = 1;
            p.setPosition(v3.init(3, 0, 0));
            try system.addParticle(p);
            p.setPosition(v3.init(0, 0, 0));
            try system.addParticle(p);

            try registry.addSpring(0, 1, 1, 1); // only p0 registered

            registry.updateForces(&system, 1.0);

            try testing.expect(v3.eq(system.forceAccum(0), v3.init(-2, 0, 0)));
            try testing.expect(v3.eq(system.forceAccum(1), v3.zero()));
        }

        test "spring - non-axis-aligned direction with scaled k and l" {
            const v3 = core.vec3(T);
            var system = particle.ParticleSystem(T).init(testing.allocator);
            defer system.deinit();
            var registry = ParticleForceRegistry(T).init(testing.allocator);
            defer registry.deinit();

            var p = particle.defaultParticle(T);
            p.inverse_mass = 1;
            p.setPosition(v3.init(3, 4, 0)); // p0 at (3,4,0), d=5
            try system.addParticle(p);
            p.setPosition(v3.init(0, 0, 0)); // p1 at origin
            try system.addParticle(p);

            try registry.addSpring(0, 1, 10, 2); // k=10, l=2

            registry.updateForces(&system, 1.0);

            // d=5, l=2, F = -(5-2)*10 = -30
            // unit = (3/5, 4/5, 0) = (0.6, 0.8, 0)
            // F = (0.6, 0.8, 0) * -30 = (-18, -24, 0)
            try testing.expect(v3.eq(system.forceAccum(0), v3.init(-18, -24, 0)));
        }

        test "anchored spring - stretched pulls toward anchor" {
            const v3 = core.vec3(T);
            var system = particle.ParticleSystem(T).init(testing.allocator);
            defer system.deinit();
            var registry = ParticleForceRegistry(T).init(testing.allocator);
            defer registry.deinit();

            var p = particle.defaultParticle(T);
            p.inverse_mass = 1;
            p.setPosition(v3.init(3, 0, 0));
            try system.addParticle(p);

            try registry.addAnchoredSpring(0, 0, 0, 0, 1, 1); // anchor at origin, k=1, l=1

            registry.updateForces(&system, 1.0);

            // d=3, l=1, F = -(3-1)*1 = -2 in x → (-2,0,0) toward anchor
            try testing.expect(v3.eq(system.forceAccum(0), v3.init(-2, 0, 0)));
        }

        test "anchored spring - compressed pushes away from anchor" {
            const v3 = core.vec3(T);
            var system = particle.ParticleSystem(T).init(testing.allocator);
            defer system.deinit();
            var registry = ParticleForceRegistry(T).init(testing.allocator);
            defer registry.deinit();

            var p = particle.defaultParticle(T);
            p.inverse_mass = 1;
            p.setPosition(v3.init(0.5, 0, 0));
            try system.addParticle(p);

            try registry.addAnchoredSpring(0, 0, 0, 0, 1, 1); // anchor at origin, k=1, l=1

            registry.updateForces(&system, 1.0);

            // d=0.5, l=1, F = -(0.5-1)*1 = +0.5 in x → (0.5,0,0) away from anchor
            try testing.expect(v3.eq(system.forceAccum(0), v3.init(0.5, 0, 0)));
        }

        test "anchored spring - at rest length applies no force" {
            const v3 = core.vec3(T);
            var system = particle.ParticleSystem(T).init(testing.allocator);
            defer system.deinit();
            var registry = ParticleForceRegistry(T).init(testing.allocator);
            defer registry.deinit();

            var p = particle.defaultParticle(T);
            p.inverse_mass = 1;
            p.setPosition(v3.init(1, 0, 0));
            try system.addParticle(p);

            try registry.addAnchoredSpring(0, 0, 0, 0, 1, 1); // anchor at origin, k=1, l=1

            registry.updateForces(&system, 1.0);

            // d=1=l → F=0
            try testing.expect(v3.eq(system.forceAccum(0), v3.zero()));
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

            const spring_slice = self.spring.slice();
            applySpring(
                T,
                slices,
                spring_slice.items(.particle_index),
                spring_slice.items(.other_particle_index),
                spring_slice.items(.k),
                spring_slice.items(.l),
                spring_slice.len,
            );

            const anchor_spring_slice = self.anchored_spring.slice();
            applyAnchoredSpring(
                T,
                slices,
                anchor_spring_slice.items(.particle_index),
                anchor_spring_slice.items(.anchor_position_x),
                anchor_spring_slice.items(.anchor_position_y),
                anchor_spring_slice.items(.anchor_position_z),
                anchor_spring_slice.items(.k),
                anchor_spring_slice.items(.l),
                anchor_spring_slice.len,
            );
        }
    };
}

test {
    _ = ParticleForceRegistry(f32);
    _ = ParticleForceRegistry(f64);
}
