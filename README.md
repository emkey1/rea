# rea

The **Rea** front end for the **PSCAL** VM, and the shared front-end engine that
**Aether** is built on. Rea parses its source into the shared PSCAL AST, which
the shared bytecode compiler lowers and the PSCAL VM runs.

Rea carries no VM or code generator of its own. It builds against
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

## Install

```sh
cmake --install build --prefix /usr/local
```

This puts the `rea` binary in `<prefix>/bin`, the example programs in
`<prefix>/share/rea/examples`, and the language docs in `<prefix>/share/doc/rea`.
The fetched `pscal-core` also installs its static library and headers under the
same prefix.

## Test

The `.rea` conformance corpus lives in [`tests/`](tests/) and runs under CTest:

```sh
ctest --test-dir build --output-on-failure
```

You can also run it directly against any binary by pointing `REA_BIN` at it
(this is how the umbrella build exercises the same corpus):

```sh
REA_BIN=./build/rea tests/run.sh
```

Fixtures that need an optional capability are skipped automatically when the
binary lacks it: the SQLite fixture skips when the `sqlite` ext-builtins are not
compiled in, and the 3D demo fixtures skip when the `3d` ext-builtins are absent.
A minimal standalone build (SDL, curl, and SQLite OFF by default) therefore stays
green.

## Examples

Runnable programs live in [`examples/`](examples/), from `base/hello` through the
object-oriented `base/showcase` and `base/hangman5` demos:

```sh
./build/rea --no-cache examples/base/hello
./build/rea --no-cache examples/base/showcase
```

The `examples/sdl/` programs need a graphics-enabled build.

## Docs

In-depth language documentation is in [`docs/`](docs/):

- [`rea_overview.md`](docs/rea_overview.md): a short tour of the language
- [`rea_tutorial.md`](docs/rea_tutorial.md): a worked introduction
- [`rea_programmers_guide.md`](docs/rea_programmers_guide.md): the full guide
- [`rea_language_reference.md`](docs/rea_language_reference.md): the reference

See [`src/rea/LANGUAGE_SPEC.md`](src/rea/LANGUAGE_SPEC.md) for the language
specification and [`src/rea/README.md`](src/rea/README.md) for the front-end
internals.
