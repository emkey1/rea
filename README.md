# rea

The **Rea** front end for the **PSCAL** VM, and the shared front-end engine that
**Aether** is built on. Rea parses its source into the shared PSCAL AST, which
the shared bytecode compiler lowers and the PSCAL VM runs.

Rea carries no VM or code generator of its own — it builds against
[`pscal-core`](https://github.com/emkey1/pscal-core), pulled in automatically via
CMake `FetchContent`.

## The shared engine

These sources double as the shared engine for both Rea and Aether. The engine
talks to "its" front end only through a small hook interface
(`src/rea/frontend_hooks.h`): the engine calls `reaFrontend*()` accessors that
default to Rea's built-in behaviour, and a front end such as Aether installs its
overrides (parse, semantic analysis, diagnostics, ...) at startup via
`reaSetFrontendHooks()`. As a result the engine has no compile- or link-time
dependency on any specific front end.

## Build

```sh
cmake -S . -B build      # fetches and builds pscal-core, then rea
cmake --build build -j
./build/rea --no-cache program.rea
```
