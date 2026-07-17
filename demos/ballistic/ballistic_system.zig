const std = @import("std");
const cyclone = @import("physics-engine");
const build_options = @import("build-options");
const testing = std.testing;

const FLOAT = switch (build_options.float) {
    .f32 => f32,
    .f64 => f64,
};

const Vec3 = cyclone.core.Vector3(FLOAT);
const v3 = cyclone.core.vec3(FLOAT);
const ParticleSystem = cyclone.particle.ParticleSystem(FLOAT);
const Particle = cyclone.particle.Particle(FLOAT);
const defaultParticle = cyclone.particle.defaultParticle;

pub const ShotType = enum(u8) {
    UNUSED = 0,
    PISTOL = 1,
    ARTILLERY = 2,
    FIREBALL = 3,
    LASER = 4,
};

const AmmoRound = struct {
    shotType: ShotType,
    startTime: u32,
};

pub const AmmoRoundSystem = struct {
    pub const CAPACITY: usize = 2000000;
    particles: ParticleSystem,
    ammoRound: std.MultiArrayList(AmmoRound),
    count: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !@This() {
        // No alloc in running time
        var ammo = std.MultiArrayList(AmmoRound){};
        try ammo.ensureTotalCapacity(alloc, CAPACITY);
        var particles = ParticleSystem.init(alloc);
        try particles.ensureTotalCapacity(CAPACITY);

        for (0..CAPACITY) |_| {
            const i = ammo.addOneAssumeCapacity();
            ammo.items(.shotType)[i] = ShotType.UNUSED;
            ammo.items(.startTime)[i] = 0;
            try particles.addParticle(defaultParticle(FLOAT));
        }

        return .{
            .ammoRound = ammo,
            .allocator = alloc,
            .particles = particles,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.particles.deinit();
        self.ammoRound.deinit(self.allocator);
    }

    test "init/deinit" {
        var system = try AmmoRoundSystem.init(testing.allocator);
        defer system.deinit();
    }

    //  busca primer UNUSED, escribe campos del particle in-site según shot (valores de cyclone),
    //  setea shotType/startTime, limpia forceAccum. count++. Si no hay slot, no hace nada.
    pub fn fire(self: *@This(), shot: ShotType, now: u32) void {
        const slice = self.ammoRound.slice();
        const shotTypes = slice.items(.shotType);

        for (0..slice.len) |i| {
            if (shotTypes[i] == ShotType.UNUSED) {
                self.ammoRound.set(i, .{
                    .shotType = shot,
                    .startTime = now,
                });
                self.count += 1;
                self.setParticle(i, shot);
                break;
            }
        }
    }

    fn setParticle(self: *@This(), index: usize, shot: ShotType) void {
        var particle = defaultParticle(FLOAT);
        switch (shot) {
            .PISTOL => {
                particle.inverse_mass = 0.5; // mass = 2kg
                particle.setVelocity(v3.init(0, 0, 35));
                particle.setAcceleration(v3.init(0, -1, 0));
                particle.damping = 0.99;
            },
            .ARTILLERY => {
                particle.inverse_mass = 0.005; // mass = 200kg
                particle.setVelocity(v3.init(0, 30, 40));
                particle.setAcceleration(v3.init(0, -20, 0));
                particle.damping = 0.99;
            },
            .FIREBALL => {
                particle.inverse_mass = 1; // mass = 1kg
                particle.setVelocity(v3.init(0, 0, 10));
                particle.setAcceleration(v3.init(0, 0.6, 0));
                particle.damping = 0.9;
            },
            .LASER => {
                particle.inverse_mass = 10; // mass = 0.1kg
                particle.setVelocity(v3.init(0, 0, 100));
                particle.setAcceleration(v3.init(0, 0, 0));
                particle.damping = 0.99;
            },
            .UNUSED => unreachable,
        }

        particle.setPosition(v3.init(0, 1.5, 0));
        particle.setForceAccum(v3.zero());

        self.particles.data.set(index, particle);
    }

    test "fire" {
        var system = try AmmoRoundSystem.init(testing.allocator);
        defer system.deinit();
        system.fire(ShotType.ARTILLERY, 1);
        system.fire(ShotType.FIREBALL, 2);
        system.fire(ShotType.LASER, 3);
        system.fire(ShotType.PISTOL, 4);
    }

    /// Updates physics and culls expired/out-of-bounds rounds.
    /// dt: frame duration in seconds. now: current timestamp in ms.
    pub fn update(self: *@This(), dt: FLOAT, now: u32) !void {
        if (dt <= 0) return;

        // Integrate all particles once (handles all CAPACITY slots,
        // including UNUSED - must change in the future).
        try self.particles.integrateAll(dt);
        defer self.particles.clearForceAccums();

        // Cull: mark UNUSED any round that hit ground, expired, or flew past z=200.
        const ammo_slice = self.ammoRound.slice();
        const shotTypes = ammo_slice.items(.shotType);
        const startTimes = ammo_slice.items(.startTime);

        const positions_y = self.particles.data.slice().items(.position_y);
        const positions_z = self.particles.data.slice().items(.position_z);

        for (0..CAPACITY) |i| {
            if (shotTypes[i] == ShotType.UNUSED) continue;

            if (positions_y[i] < 0 or now - startTimes[i] > 5000 or positions_z[i] > 200) {
                shotTypes[i] = ShotType.UNUSED;
                self.count -= 1;
            }
        }
    }
};

test {
    _ = AmmoRoundSystem;
}
