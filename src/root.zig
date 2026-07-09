//! By convention, root.zig is the root source file when making a library.
//! Having the public stuff of the module.
const core = @import("cyclone/core.zig");
const particle = @import("cyclone/particle.zig");

pub const Vector3 = core.Vector3;
pub const Particle = particle.Particle;
pub const ParticleSystem = particle.ParticleSystem;

pub const defaultParticle = particle.defaultParticle;

test {
    _ = core;
    _ = particle;
}
