const std = @import("std");
const raylib = @import("raylib");
const builtin = @import("builtin");

const Demo = struct {
    name: []const u8,
    source: []const u8,
    test_source: ?[]const u8,
};

const demos = [_]Demo{
    .{
        .name = "ballistic",
        .source = "demos/ballistic/ballistic.zig",
        .test_source = "demos/ballistic/ballistic_system.zig",
    },
};

const Target = enum {
    native,
    web,
};

const Float = enum {
    f32,
    f64,
};

// Result example: const DemoName = enum(u8) { ballistic = 0 };
const DemoName = blk: {
    var names: [demos.len][]const u8 = undefined;
    var values: [demos.len]u8 = undefined;
    for (demos, 0..) |d, i| {
        names[i] = d.name;
        values[i] = i;
    }
    break :blk @Enum(u8, .exhaustive, &names, &values);
};

// Result example: const ModuleName = enum(u8) { @"physics-engine" = 0, ballistic = 1 };
const ModuleName = blk: {
    var count: usize = 1;
    for (demos) |d| {
        if (d.test_source != null) count += 1;
    }

    var names: [count][]const u8 = undefined;
    var values: [count]u8 = undefined;
    names[0] = "physics-engine";
    values[0] = 0;
    var idx: usize = 1;
    for (demos) |d| {
        if (d.test_source != null) {
            names[idx] = d.name;
            values[idx] = @intCast(idx);
            idx += 1;
        }
    }
    break :blk @Enum(u8, .exhaustive, &names, &values);
};

// Helpers
fn addPhysicsMod(
    b: *std.Build,
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.addModule(name, .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
}

const RenderArtifacts = struct {
    mod: *std.Build.Module,
    raylib_lib: *std.Build.Step.Compile,
};

fn addRenderMod(
    b: *std.Build,
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    physics_mod: *std.Build.Module,
) RenderArtifacts {
    const render_mod = b.addModule(name, .{
        .root_source_file = b.path("demos/render.zig"),
        .target = target,
        .optimize = optimize,
    });

    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib_lib = raylib_dep.artifact("raylib");
    render_mod.linkLibrary(raylib_lib);
    render_mod.link_libc = true;
    render_mod.addImport("physics-engine", physics_mod);
    return .{ .mod = render_mod, .raylib_lib = raylib_lib };
}

fn addDemoExe(
    b: *std.Build,
    demo: Demo,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    physics_mod: *std.Build.Module,
    render_mod: *std.Build.Module,
    options_mod: *std.Build.Module,
) *std.Build.Step.Compile {
    const demo_exe = b.addExecutable(.{
        .name = b.fmt("{s}_desktop", .{demo.name}),
        .root_module = b.createModule(.{
            .root_source_file = b.path(demo.source),
            .target = target,
            .optimize = optimize,
        }),
    });

    demo_exe.root_module.addImport("physics-engine", physics_mod);
    demo_exe.root_module.addImport("render", render_mod);
    demo_exe.root_module.addImport("build-options", options_mod);
    return demo_exe;
}

fn addDemoWebLib(
    b: *std.Build,
    demo: Demo,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    physics_mod: *std.Build.Module,
    render_mod: *std.Build.Module,
    options_mod: *std.Build.Module,
) *std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .name = b.fmt("{s}_web", .{demo.name}),
        .root_module = b.createModule(.{
            .root_source_file = b.path(demo.source),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    lib.root_module.addImport("physics-engine", physics_mod);
    lib.root_module.addImport("render", render_mod);
    lib.root_module.addImport("build-options", options_mod);
    return lib;
}

fn addEmccStep(
    b: *std.Build,
    raylib_lib: *std.Build.Step.Compile,
    lib: *std.Build.Step.Compile,
    optimize: std.builtin.OptimizeMode,
    install_dir: std.Build.InstallDir,
) *std.Build.Step {
    const emcc_flags = raylib.emsdk.emccDefaultFlags(b.allocator, .{ .optimize = optimize, .asyncify = false });
    const emcc_settings = raylib.emsdk.emccDefaultSettings(b.allocator, .{ .optimize = optimize });
    return raylib.emsdk.emccStep(b, raylib_lib, lib, .{
        .optimize = optimize,
        .flags = emcc_flags,
        .settings = emcc_settings,
        .shell_file_path = b.path("demos/web/shell.html"),
        .install_dir = install_dir,
    });
}

pub fn build(b: *std.Build) void {
    // Default target and optimization
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const demo_opt = b.option(DemoName, "demo", "Which demo to build (default: all)");
    const target_opt = b.option(Target, "build-target", "Which target (default: native and web)");
    const float_opt = b.option(Float, "float", "Float precision (default: f32)") orelse .f32;
    const perf_opt = b.option(bool, "perf", "ReleaseFast + LLVM + native CPU") orelse false;
    const module_opt = b.option(ModuleName, "module", "Module to test (required for 'test' step)");

    const eff_optimize: std.builtin.OptimizeMode = if (perf_opt) .ReleaseFast else optimize;

    if (perf_opt and target_opt != null and target_opt.? == .web) {
        std.debug.print("Error: -Dperf implies native target, cannot use -Dtarget=web\n", .{});
        return;
    }

    // Build-options (-Dfloat)
    const options_step = b.addOptions();
    options_step.addOption(Float, "float", float_opt);
    const options_mod = options_step.createModule();

    // Physics module base (native/host para demos nativos y tests)
    const native_target = if (perf_opt)
        b.resolveTargetQuery(.{
            .cpu_arch = builtin.cpu.arch,
            .cpu_model = .native,
        })
    else
        target;

    const physics_mod = addPhysicsMod(b, "physics-engine", native_target, eff_optimize);

    // ========================================================================
    // INSTALL (default: zig build) — demos filtrados por -Ddemo / -Dtarget / -Dperf
    // ========================================================================

    // Native demos
    if (target_opt == null or target_opt.? == .native) {
        const render_native = addRenderMod(b, "render", native_target, eff_optimize, physics_mod);

        for (demos) |demo| {
            if (demo_opt) |want| {
                if (!std.mem.eql(u8, demo.name, @tagName(want)))
                    continue;
            }

            const exe = addDemoExe(
                b,
                demo,
                native_target,
                eff_optimize,
                physics_mod,
                render_native.mod,
                options_mod,
            );
            if (perf_opt) {
                exe.use_llvm = true;
                exe.use_lld = true;
            }

            const install_exe = b.addInstallArtifact(exe, .{
                .dest_dir = .{ .override = .{ .custom = b.fmt("{s}/bin", .{demo.name}) } },
            });

            b.getInstallStep().dependOn(&install_exe.step);
        }
    }

    // Web demos
    if ((target_opt == null or target_opt.? == .web) and !perf_opt) {
        const web_target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .emscripten,
        });

        const physics_mod_web = addPhysicsMod(b, "physics-engine", web_target, optimize);
        const render_mod_web = addRenderMod(b, "render", web_target, optimize, physics_mod_web);

        for (demos) |demo| {
            if (demo_opt) |want| {
                if (!std.mem.eql(u8, demo.name, @tagName(want)))
                    continue;
            }

            const web_lib = addDemoWebLib(
                b,
                demo,
                web_target,
                optimize,
                physics_mod_web,
                render_mod_web.mod,
                options_mod,
            );

            const emcc = addEmccStep(
                b,
                render_mod_web.raylib_lib,
                web_lib,
                optimize,
                .{ .custom = b.fmt("{s}/web", .{demo.name}) },
            );
            b.getInstallStep().dependOn(emcc);
        }
    }

    // ========================================================================
    // STEP: test  (zig build test [-Dmodule=...])
    // ========================================================================
    const test_step = b.step("test", "Run tests");

    const engine_test = b.addTest(.{
        .name = "physics-engine",
        .root_module = physics_mod,
    });
    test_step.dependOn(&b.addRunArtifact(engine_test).step);

    for (demos) |demo| {
        if (module_opt) |want| {
            if (!std.mem.eql(u8, demo.name, @tagName(want)))
                continue;
        }
        if (demo.test_source) |test_src| {
            const demo_test_mod = b.createModule(.{
                .root_source_file = b.path(test_src),
                .target = target,
                .optimize = optimize,
            });
            demo_test_mod.addImport("physics-engine", physics_mod);
            demo_test_mod.addImport("build-options", options_mod);
            const demo_test = b.addTest(.{
                .name = demo.name,
                .root_module = demo_test_mod,
            });
            test_step.dependOn(&b.addRunArtifact(demo_test).step);
        }
    }

    // ========================================================================
    // STEP: perf  (zig build perf) — engine tests con AVX2
    // ========================================================================
    const perf_step = b.step("perf", "Engine tests with ReleaseFast + LLVM + native CPU");
    const perf_target = b.resolveTargetQuery(.{
        .cpu_arch = builtin.cpu.arch,
        .cpu_model = .native,
    });
    const physics_perf_mod = addPhysicsMod(b, "physics-engine", perf_target, .ReleaseFast);
    const perf_tests = b.addTest(.{ .root_module = physics_perf_mod });
    if (perf_opt) {
        perf_tests.use_llvm = true;
        perf_tests.use_lld = true;
    }
    perf_step.dependOn(&b.addRunArtifact(perf_tests).step);
}
