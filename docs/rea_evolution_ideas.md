# Rea Evolution Ideas — cross-pollination from Aether

A running list of engine/AST-level work done for Aether that Rea could adopt,
plus general directions if Rea grows into a more general-purpose (potentially
agentic) language.  Aether stays focused and specialized; Rea is the natural
home for the fuller-featured sibling on the same shared engine and VM.

Seeded 2026-07-01 during the Aether frontend hardening pass (rewriter
retirement + fx/purity-on-AST + diagnostics work).  Append here whenever
Aether-motivated work produces something the shared engine or Rea's own
frontend could reuse.

## Already shared (Rea benefits today or nearly for free)

- **Constant record-field defaults.**  `emitDefaultFieldInitializers` landed in
  pscal-core's compiler (2026-07-01-4, FIELD-003 work), applied on top of the
  type zero at `new`.  The backend half is done; Rea only needs the surface
  syntax (`x: int = 0;` in a class body) wired to the same field-default
  attachment on `AST_VAR_DECL`.
- **Single-source effectfulness registry.**  `pscalBuiltinNameIsEffectful()`
  (pscal-core builtin.c) classifies every builtin.  Rea could offer an opt-in
  purity annotation checked against the same registry with zero new
  bookkeeping.
- **Builtin discovery/introspection.**  `builtins_json(true)` / `builtin_info`
  metadata (signature, return type, effectful, category) is frontend-neutral;
  surfacing it in Rea makes Rea equally agent-discoverable.

## Portable with modest effort

- **Coded diagnostics + repair hints.**  The frontend-hooks seam already
  carries `inferDiagnosticCode`, and the `--diagnostics-json` collector
  backfills codes via the registered frontend.  Rea could define its own code
  map (or share Aether's taxonomy where rules coincide) and gain the same
  LLM-repair-loop ergonomics.  The Aether lesson worth porting *properly*:
  pass explicit codes at emission sites; substring inference on message text
  is fragile.
- **Silent-failure backstop.**  Aether funnels every parser diagnostic through
  one counting sink and emits a guaranteed coded error if a parse fails with
  zero messages (`ast_parser.c` 2026-07-01-1).  Rea's parser has the same
  latent risk class; the pattern is small and mechanical.
- **Contract annotations.**  Aether's `@pre`/`@post` lower to plain AST guard
  code (`if (!(e)) { writeln(...); halt(1); }`) — no backend support needed.
  Rea could adopt the same annotations on methods/functions almost verbatim;
  the guard builder is generic AST construction.
- **`par`-style structured parallelism.**  Aether's `par { f(); g(); }` lowers
  to the existing rea thread builtins (spawn/join).  The lowering plus the
  PAR-001 shared-record compile-time check would give Rea a safe structured
  concurrency block for free conceptually — and a *proper* alias analysis (the
  current check is name-based) would be a shared-engine improvement both
  frontends inherit.

## Shared-engine (rea lexer/AST) improvements Aether would also benefit from

- **A real `..` range token.**  Rea's lexer shreds `0..5` into two malformed
  numbers (`0.` / `.5`); Aether reconstructs the range with a re-tokenizing
  layer and a synthetic token.  Adding a genuine DOTDOT token to the shared
  lexer would delete that whole hack and give Rea range syntax if it wants it.
- **Tuple values done right.**  Aether's tuple returns currently lower to
  per-slot globals (non-reentrant: recursion/threads corrupt them).  If tuples
  are ever wanted seriously — in either language — the correct home is a small
  shared-AST/codegen facility (per-call temporaries), not a frontend trick.
  Worth doing once, in the engine, for both.
- **Effect regions on the AST.**  The Aether fx-on-AST work (2026-07-01) marks
  effect blocks on shared AST nodes so semantic passes can walk them.  If that
  marker lives in the shared AST (rather than an Aether side table), Rea can
  reuse it for any future effect/purity story.  Implementation lesson from
  shipping it as side tables: the checks actually needed two node-identity
  facts — `is_effect_region` AND `is_compiler_synthesized` (injected @pre/@post
  guard bodies call writeln/halt and must be exempt) — so an engine-level
  design should budget two AST node flags, not one; flags also survive
  `copyAST` where pointer-keyed side tables silently do not.

## Direction notes (Rea as a general-purpose agentic language)

- Rea already has the OOP/class model Aether deliberately excludes; the
  complementary positioning is: Aether = narrow, one-spelling, no-guide
  generation; Rea = the fuller general-purpose sibling (richer stdlib,
  general-purpose ergonomics) without violating Aether's design rules.
- **Closures: decided against for now (owner, 2026-07-01).**  Rea is a
  traditional OOP language, and objects already cover the closure use cases
  (captured state = fields, behavior = a method); real capturing closures
  would add a second competing idiom, a new VM value kind, capture-semantics
  choices, captured-frame lifetimes, and would hide effects from any future
  purity/effect checks.  If a Rea benchmark ever shows HOF-shaped failures
  dominating, the measured middle step is **named function/bound-method
  references** (no environment capture): callbacks and `map(xs, double)`
  shapes, statically checkable, composing with OOP instead of competing with
  it.  Capturing closures stay off the roadmap unless the instrument demands
  them.
- The Aether benchmark harness (doc-variant scoring, repair loop, generative
  idea-mining) is language-agnostic in structure; pointing it at Rea would
  give the same empirical design instrument before investing in new features.
- Feasibility caveat (owner's note): Rea carries existing design history and
  an installed base of engine behavior; evolve additively (new opt-in surface,
  shared-engine facilities) rather than re-founding it.
- Diagnostics-JSON collector (src/rea/main.c): the standalone `help: see
  CODE ...` guide-pointer line that follows a coded diagnostic is captured as
  its own junk entry (severity error, kind generic, code null). Folding it
  into the preceding diagnostic (like the existing `hint:` handling) would
  keep the machine-readable stream one-entry-per-problem; observed while
  wiring Aether's TYPE-001/TOON-001 semantic codes.
