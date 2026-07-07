# PLAN — Motor de físicas `fisicas`

Port de `cyclone-physics` (C++) a Zig 0.15.2, con desarrollo Data-Oriented,
motor puro independiente, demos con RayLib (nativo y web vía emscripten),
y multihilo web vía Web Workers.

---

## Contexto y decisiones de diseño

### Objetivos
- Portar el motor de `cyclone-physics/` a Zig 0.15.2.
- Desarrollo **Data-Oriented** (DoD): SoA interno en los sistemas.
- Motor **puro e independiente** del rendering.
- **Demos con RayLib** desde el inicio, tanto **nativas** (desktop, OpenGL)
  como **web** (navegador, WebGL vía **emscripten**).
- **Multihilo** nativo y, en web, vía **Web Workers** (emscripten +
  `USE_PTHREADS`).
- Ampliaciones futuras: **GJK, fluidos, multihilo**.
- Desarrollo en solitario; la IA se usa solo como fuente de documentación,
  no toca el código.

### Decisiones tomadas
1. **Motor puro** (sin dependencias de rendering). Se valida con
   `zig build test` y se importa como módulo Zig por las demos; no se
   compila a WASM por sí solo.
2. **DoD con SoA interno**: structs de instancia como tipos de entrada,
   SoA solo como layout de almacenamiento en los sistemas (como ya hace
   `ParticleSystem` con `std.MultiArrayList`).
3. **f32 en demos web** (rendimiento), **f64 en tests/depuración nativa**.
4. **Hosting estático cliente**: el bundle emscripten
   (`index.html`/`.js`/`.wasm`) se sube a **Netlify / Cloudflare Pages /
   itch.io** (no GitHub Pages). El navegador del usuario ejecuta el wasm.
   Sin servidores ni render server-side. Se descarta GitHub Pages porque
   no permite servir las cabeceras COOP/COEP que exige el multihilo web
   (ver #7).
5. **RayLib es el único motor de rendering**, para demos **nativas y web**.
   La vía web se hace con **emscripten desde el inicio** (no es un
   experimento futuro).
6. **RayLib se integra vía bindings C directos** (`@cImport("raylib.h")`
   o equivalente sobre la fuente C de raylib), **no** vía `raylib-zig`,
   para evitar el acoplamiento de versión Zig y los problemas de
   compatibilidad futura que tendría un wrapper de terceros.
7. **Emscripten habilita multihilo en web** con **Web Workers**
   (`-s USE_PTHREADS=1`), además del bucle principal por callback, WebGL y
   GLFW emulado. Pthreads en el navegador exige que el servidor sirva:
   - `Cross-Origin-Opener-Policy: same-origin`
   - `Cross-Origin-Embedder-Policy: require-corp`
   Por eso el hosting es Netlify / Cloudflare Pages / itch.io (que
   permiten estas cabeceras), no GitHub Pages.
8. **Orden de portado**: partículas primero (`pfgen` → `plinks` →
   `pcontacts` → `pworld`), luego rigid bodies.

### Nota técnica sobre RayLib + web (emscripten)
RayLib para web (`PLATFORM_WEB` / `rcore_web.c`) **requiere emscripten**:
usa APIs `emscripten_*`, GLFW vía `USE_GLFW=3`, WebGL emulado, main-loop
por callback vía `emscripten_set_main_loop` (sin ASYNCIFY) y,
opcionalmente, `USE_PTHREADS` para Web Workers. No existe plataforma web
pura-wasm32-freestanding en RayLib upstream, por lo que `zig cc -target
wasm32` **no puede** compilar RayLib a web por sí solo.

Mecanismo de build web previsto: **Zig compila el motor + la demo a
objetos `wasm32-emscripten`** (usando el target emscripten de Zig y/o
`zig cc` como backend C de emcc), y **`emcc` enlaza** el resultado con
raylib (compilado con emcc, `-DPLATFORM_WEB -DGRAPHICS_API_OPENGL_ES2`),
WebGL, el runtime de emscripten y, cuando proceda, pthreads.

> ⚠️ **Parte más delicada.** El acoplamiento exacto entre `zig build` y
> `emcc` (cómo se pasan objetos, flags `-s`, `--shell-file`, main-loop por
> callback, export de memoria, pthreads) es lo más probable de requerir
> iteración durante la Fase 1. Si atasca el slice vertical, el plan de
> contingencia es: `demo-native` primero (OpenGL desktop, ya funciona),
> `demo-web` (emscripten) como segundo paso de la misma fase.

---

## Arquitectura por capas

```
┌─────────────────────────────────────────────────────────────────┐
│  CAPA 1 — MOTOR (fisicas/)                                      │
│  Zig puro, comptime T, DoD/SoA interno. Sin rendering, sin SO.  │
│  ├─ zig build test     → tests (f64)                            │
│  └─ módulo importable por demos (@import("fisicas"))           │
└─────────────────────────────────────────────────────────────────┘
        ▲ import (@import("fisicas"))
        │
┌───────┴──────────────────────────────────────────┐
│  CAPA 2 — Demos RayLib (unificadas)              │
│  raylib (vía @cImport) + módulo fisicas          │
│  ├─ zig build demo-native → exe desktop (OpenGL) │
│  └─ zig build demo-web    → html/js/wasm (WebGL) │
└──────────────────────────────────────────────────┘
                            ▲
                            │ hosting estático
                   ┌────────┴────────┐
                   │  CAPA 3 — Nube   │
                   │  Pages/Netlify/  │
                   │  itch.io         │
                   └─────────────────┘
```

### Targets de build

| Build              | Comando                | Salida                | Rendering              |
|--------------------|------------------------|-----------------------|------------------------|
| Motor (tests)      | `zig build test`       | —                     | —                      |
| Demo RayLib nativa | `zig build demo-native`| exe desktop           | RayLib / OpenGL nativo |
| Demo RayLib web    | `zig build demo-web`   | `index.html`/`.js`/`.wasm` | RayLib / WebGL (emscripten) |

> RayLib (vía `@cImport("raylib.h")`) vive en la **demo**, no en el motor.
> El motor nunca importa raylib. Así `zig build test` no se ve afectado
> por raylib ni por su compatibilidad con Zig 0.15.2; solo `demo-native` y
> `demo-web` dependen de raylib.

---

## Estructura de módulos propuesta

```
fisicas/
├── build.zig                  (editar: steps `demo-native` y `demo-web`)
├── build.zig.zon              (dep raylib/fuente C solo en los steps de demo)
├── src/
│    ├── cyclone/
│    │   ├── core.zig           ✓ Vector3 (falta Quaternion, Matrix4)
│    │   ├── particle.zig       ✓ Particle + ParticleSystem (SoA)
│    │   ├── pcontacts.zig      (futuro: contactos partículas)
│    │   ├── pfgen.zig          (futuro: force generators)
│    │   ├── plinks.zig         (futuro: constraints/links)
│    │   ├── pworld.zig         (futuro: ParticleWorld)
│    │   └── cyclone.zig        (re-exports)
│    └── root.zig               (lib pública: re-exporta cyclone)
└── demos/
    ├── ballistic.zig              ← fuente única (native + web): @import("fisicas") + @cImport("raylib.h")
    └── web/
        └── shell.html             ← plantilla emscripten para demo-web
```

Notas:
- **Sin `src/wasm/kernel.zig`**: no hay superficie C ABI ni estado global
  del motor para WASM; la demo se compila entera (motor + raylib) a cada
  target.
- **Sin `src/main.zig` / exe `fisicas` standalone**: cada demo es su
  propio `root_source_file` en su step de build (`demos/ballistic.zig`).
- **Fuente única**: `demos/ballistic.zig` se compila tanto por
  `demo-native` como por `demo-web`; solo difieren el target, las flags
  de raylib/emscripten y la `shell.html`.
- `src/cyclone/particle-poo.zig` (versión OOP anterior) se conserva como
  referencia.

---

## Convenciones DoD (aplicables a todo lo nuevo)

- **Entidades = POD structs** (sin métodos de comportamiento, solo datos).
  `Particle`, `Body`, etc. son tipos de dato, no objetos.
- **Sistemas = structs con `std.MultiArrayList(EntityType)`** (SoA interno).
  La lógica (integración, contacto, fuerza) vive en el Sistema, no en la
  entidad.
- **`comptime T: type`** en todos los tipos (`f32` por defecto en demos
  web, `f64` para tests/depuración nativa).
- **Allocators explícitos**: `init(allocator)` → sistema owns su memoria →
  `deinit()` libera. Sin allocator global.
- **Sin allocations en hot path**: pre-asignar capacidad con
  `ensureTotalCapacity` al inicio del frame/escena; `addX` solo falla si no
  cabe. El `integrateAll`/`runPhysics` no debe allocar.
- **Errors**: `error{OutOfMemory, ...}` explícitos.
- **Tests junto al código**: `test "..."` por función pública.
- **Re-exports** centralizados en `src/cyclone/cyclone.zig` (y
  `src/root.zig` hacia fuera).
- **Datos de escena no-físicos** (lifetimes, flags de spawn, estado de
  demo) en arrays paralelos de la **demo/escena**, **no** en entidades del
  motor.

---

## Fase 1 — Slice vertical (demo balístico con RayLib, nativa + web)

Réplica minimal del demo `ballistic` de cyclone: varios proyectiles
(pistol, artillery, fireball, laser) disparados con velocidades distintas,
todos bajo gravedad, sin colisiones (solo integración). Usa **solo
`ParticleSystem(f32)` + `Vector3(f32)`** ya implementados, renderizados con
RayLib.

### 1.1 `demos/ballistic.zig` (nueva fuente única)
- Importa `@import("fisicas")` (módulo del motor) y raylib vía
  `@cImport("raylib.h")` (bindings C directos, no `raylib-zig`).
- Crea un `ParticleSystem(f32)` local (no global del motor), spawn de los
  4 proyectiles con gravedad.
- **Lógica del frame extraída a `updateDrawFrame()`** (físicas + render:
  `BeginDrawing`/`EndDrawing`, `step(1/60)` del sistema, `DrawSphere` por
  proyectil con cámara `Camera3D`).
- **Bucle por plataforma, detectado en compile-time** (sin ASYNCIFY):

 

```zig
  // 1. Encapsular el estado en un struct
  const DemoState = struct {
    world: phys.World,
    // ...
  };

  // 2. El callback que recibe el estado vía puntero opaco (C ABI)
  fn updateDrawFrame(arg: ?*anyopaque) callconv(.C) void {
    const state: *DemoState = @ptrCast(@alignCast(arg.?));
    // Físicas (state.world.step...) y Renderizado (rl.DrawSphere...)
  }

  pub fn main() !void {
    // ... inicializar Raylib ...

    // 3. Crear el estado en el HEAP para que sobreviva en la web
    const state = try allocator.create(DemoState);
    state.* = .{ .world = phys.World.init(allocator) };

    const is_web = @import("builtin").os.tag == .emscripten;

    if (is_web) {
        const em = @cImport({ @cInclude("emscripten.h"); });
        // Pasamos la función Y el puntero al estado
        em.emscripten_set_main_loop_arg(updateDrawFrame, state, 0, 1);
    } else {
        // En escritorio, pasamos el estado manualmente
        while (!rl.WindowShouldClose()) updateDrawFrame(state);
    }
  }
```

- Tecla `R` → resetea posiciones/velocidades para re-disparar.
- Misma fuente para `demo-native` y `demo-web`.

### 1.2 `build.zig` — step `demo-native`
- `addExecutable` con target nativo, root source `demos/ballistic.zig`.
- Compila raylib desde su fuente C con `zig cc` (o enlaza `libraylib.a`
  prebuilt) con `PLATFORM_DESKTOP` + backend GL del SO.
- Expone `raylib.h` a la demo vía `@cImport`.
- Top-level step `demo-native`.
- Comando: `zig build demo-native` → `zig-out/bin/ballistic` (desktop,
  OpenGL).

### 1.3 `build.zig` — step `demo-web` (emscripten)
- Target `wasm32-emscripten`; zig compila motor + demo a objetos y `emcc`
  enlaza con raylib (`PLATFORM_WEB`, `GRAPHICS_API_OPENGL_ES2`) +
  `-s USE_GLFW=3`, WebGL, `--shell-file demos/web/shell.html`. **Sin
  ASYNCIFY**: el main-loop se delega a emscripten vía
  `emscripten_set_main_loop` desde la propia demo (ver 1.1).
- Top-level step `demo-web`.
- Comando: `zig build demo-web` → `zig-out/bin/ballistic.html` +
  `.js`/`.wasm` (WebGL).
- Opcional (multihilo futuro): `-s USE_PTHREADS=1` para Web Workers
  (requiere COOP/COEP en el hosting, ver Fase 2).

### 1.4 `demos/web/shell.html`
- Plantilla mínima de emscripten: canvas + carga del `.js` glue generado
  por `emcc`. Sin JS de física propio (RayLib pinta el canvas).

### 1.5 Validación
- `zig build test` (tests existentes de `core`/`particle` con f64).
- `zig build demo-native` → abre el exe, ver los 4 proyectiles volando en
  3D con gravedad.
- `zig build demo-web` → servir `zig-out/bin/` (ej.
  `python -m http.server`) y abrir `ballistic.html` en el navegador.
- **Contingencia**: si el enlace emscripten atasca, entregar primero
  `demo-native` y dejar `demo-web` como segundo paso de la misma fase.

---

## Fase 2 — Despliegue (hosting estático cliente)

- Copiar el bundle `zig-out/bin/ballistic.{html,js,wasm}` a la raíz de un
  sitio en **Netlify** o **Cloudflare Pages** (renombrando
  `ballistic.html` → `index.html` si procede). itch.io también sirve para
  publicar builds web.
- **GitHub Pages no sirve**: no permite configurar cabeceras HTTP, y el
  multihilo web (pthreads/Web Workers) exige:
  - `Cross-Origin-Opener-Policy: same-origin`
  - `Cross-Origin-Embedder-Policy: require-corp`
- Configurar las cabeceras en el hosting. Ejemplo `netlify.toml`:

  ```toml
  [[headers]]
    for = "/*"
    [headers.values]
      Cross-Origin-Opener-Policy = "same-origin"
      Cross-Origin-Embedder-Policy = "require-corp"
  ```

  Equivalente en Cloudflare Pages con un fichero `_headers`:

  ```
  /*
    Cross-Origin-Opener-Policy: same-origin
    Cross-Origin-Embedder-Policy: require-corp
  ```

- 0 servidores, 0 runtime en la nube. El navegador del usuario ejecuta el
  wasm y renderiza WebGL. Si en algún momento se prescinde de pthreads,
  GitHub Pages volvería a ser viable, pero como pthreads es parte del
  plan se asume hosting con cabeceras desde el inicio.

---

## Fase 3 — Portado del motor (futuro, fuera del slice vertical)

Con la arquitectura fijada y el slice vertical funcionando, portar en
orden siguiendo el libro de cyclone:

### 3.1 Sistema de partículas (completar)
1. `pfgen.zig` — force generators (gravity, drag, spring, buoyancy…).
2. `plinks.zig` — constraints (rods, cables).
3. `pcontacts.zig` — resolución de contactos entre partículas.
4. `pworld.zig` — orquestador: integrar, force-gen, contactos, resolver.

### 3.2 Rigid bodies
1. `core.zig`: añadir `Quaternion(T)` y `Matrix4(T)` (necesarios para
   orientación y transformaciones de bodies).
2. `body.zig` — `RigidBody` + `RigidBodySystem` (SoA).
3. `fgen.zig` — force generators para bodies.
4. `contacts.zig` — contactos y resolución entre bodies.
5. `joints.zig` — joints entre bodies.
6. `world.zig` — `World` orquestador de rigid bodies.

### 3.3 Colisiones
1. `collide_coarse.zig` — detección broad phase (BVH / spatial hash).
2. `collide_fine.zig` — detección narrow phase (SAT / primitivas).

### 3.4 Ampliaciones avanzadas
- **GJK** — colisión convexa genérica.
- **Fluidos** — simulación de fluidos (SPH o similar).
- **Multihilo** — paralelización de integración / broad phase / resolución
  de contactos. Nativo con `std.Thread`; web con Web Workers vía
  emscripten (`USE_PTHREADS`).

---

## Estado actual (punto de partida)

- `src/cyclone/core.zig` — `Vector3(T)` completo con tests (f32/f64). ✓
- `src/cyclone/particle.zig` — `Particle(T)` + `ParticleSystem(T)` con
  `MultiArrayList` (SoA) e integración Newton-Euler. ✓
- `src/cyclone/particle-poo.zig` — versión OOP anterior (referencia).
- `src/cyclone/cyclone.zig` — re-exports mínimos. ✓
- `src/root.zig` — scaffolding de módulo. ✓
- `src/main.zig` — exe standalone por defecto (se elimina en la Fase 1:
  las demos pasan a ser los roots de build).
- `src/demos/app.zig` — vacío.
- `src/demos/demos/ballistic.zig` — vacío.
- `build.zig` / `build.zig.zon` — scaffolding por defecto de Zig 0.15.2.

Módulos de cyclone (C++) aún no portados: `core` (Quaternion/Matrix4),
`pcontacts`, `pfgen`, `plinks`, `pworld`, `body`, `contacts`, `fgen`,
`joints`, `world`, `collide_coarse`, `collide_fine`, `random`.
