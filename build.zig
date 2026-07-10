const std = @import("std");
const raylib = @import("raylib");

pub fn build(b: *std.Build) void {
    // Default target and optimization
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ========================================================================
    // ENGINE
    // ========================================================================
    const physics_mod = b.addModule("physics-engine", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ========================================================================
    // ENGINE TESTS
    // Command: zig build engine-test --summary all
    // ========================================================================
    const mod_tests = b.addTest(.{
        .root_module = physics_mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("engine-test", "Run engine tests");
    test_step.dependOn(&run_mod_tests.step);

    // ========================================================================
    // DEMO TESTS
    // Command: zig build demo-test --summary all
    // Tests the demo logic with the engine module only.
    // ========================================================================
    const demo_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("demos/ballistic/ballistic_system.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    demo_test.root_module.addImport("physics-engine", physics_mod);

    const run_demo_tests = b.addRunArtifact(demo_test);
    const demo_test_step = b.step("demo-test", "Run demo tests (no raylib)");
    demo_test_step.dependOn(&run_demo_tests.step);

    // TODO: Check best way to compile in batches for multiple demos

    // ========================================================================
    // NATIVE DEMO
    // Command: zig build demo-native [-Doptimize=ReleaseFast] --summary all
    // ========================================================================
    const native_step = b.step("demo-native", "Compile and run demos in Desktop");

    // RENDER NATIVE

    const render_native_mod = b.addModule("render", .{
        .root_source_file = b.path("demos/render.zig"),
        .target = target,
        .optimize = optimize,
    });

    const raylib_dep_native = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib_lib_native = raylib_dep_native.artifact("raylib");

    render_native_mod.linkLibrary(raylib_lib_native);
    render_native_mod.link_libc = true;
    render_native_mod.addImport("physics-engine", physics_mod);

    const ballistic_exe = b.addExecutable(.{
        .name = "ballistic_desktop",
        .root_module = b.createModule(.{
            .root_source_file = b.path("demos/ballistic/ballistic.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Linking dependencies
    ballistic_exe.root_module.addImport("physics-engine", physics_mod);
    ballistic_exe.root_module.addImport("render", render_native_mod);

    // Installing and configuring the command for it to be executed immediately
    const install_native = b.addInstallArtifact(ballistic_exe, .{});
    const run_native = b.addRunArtifact(ballistic_exe);
    run_native.step.dependOn(&install_native.step);
    native_step.dependOn(&run_native.step);

    // ========================================================================
    // WEB DEMO
    // Command: zig build demo-web [-Doptimize=ReleaseSmall] --summary all
    // ========================================================================
    const web_step = b.step("demo-web", "Compile demos for web");

    // Creating target for web
    const web_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .emscripten,
    });

    const physics_mod_web = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = web_target,
        .optimize = optimize,
    });

    // Render web
    const render_web_mod = b.addModule("render", .{
        .root_source_file = b.path("demos/render.zig"),
        .target = web_target,
        .optimize = optimize,
    });
    render_web_mod.addImport("physics-engine", physics_mod_web);

    // Building Raylib again, but with web target
    // The internal build.zig of Raylib will detect the .os_tag and will activate PLATFORM_WEB
    const raylib_dep_web = b.dependency("raylib", .{
        .target = web_target,
        .optimize = optimize,
    });

    const raylib_lib_web = raylib_dep_web.artifact("raylib");

    render_web_mod.linkLibrary(raylib_lib_web);
    render_web_mod.link_libc = true;

    // Link static library
    const lib_web = b.addLibrary(.{
        .name = "ballistic_web",
        .root_module = b.createModule(.{
            .root_source_file = b.path("demos/ballistic/ballistic.zig"),
            .target = web_target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });

    lib_web.root_module.addImport("physics-engine", physics_mod_web);
    lib_web.root_module.addImport("render", render_web_mod);

    // This activates the donwload emsdk through raylib, calls emcc
    // with raylib + lib and creates html, js and wasm
    const emcc_flags = raylib.emsdk.emccDefaultFlags(b.allocator, .{
        .optimize = optimize,
        .asyncify = false,
    });

    const emcc_settings = raylib.emsdk.emccDefaultSettings(b.allocator, .{
        .optimize = optimize,
    });

    const emcc_step = raylib.emsdk.emccStep(b, raylib_lib_web, lib_web, .{
        .optimize = optimize,
        .flags = emcc_flags,
        .settings = emcc_settings,
        .shell_file_path = b.path("demos/web/shell.html"),
        .install_dir = .{ .custom = "web" },
    });

    web_step.dependOn(emcc_step);
}
