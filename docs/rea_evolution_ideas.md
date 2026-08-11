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

- **Constant record-field defaults — DONE (2026-07-01).**  Rea class bodies
  accept `int count = 0;` style constant defaults, applied at `new` on top of
  the type zero, with the same FIELD-003 constant boundary as Aether
  (non-constant defaults rejected at parse time; constructor and
  `new T { field: v }` overrides win).  Backend was already in pscal-core.
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
- **Silent-failure backstop — DONE (2026-07-01).**  Rea's parser now funnels
  all diagnostics through a counting sink (`reaDiagf`) and emits a guaranteed
  fallback syntax error at the stalled token when a parse fails with zero
  messages, mirroring aether's pattern.
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
- Diagnostics-JSON collector help:-line junk entry — FIXED (2026-07-01):
  `help:` lines now fold into the preceding diagnostic's hint like `hint:`
  lines, so a coded diagnostic is one JSON entry.
- Unknown-type diagnostics gap (found during the 2026-07-01 forward-reference
  fix): a field/var typed with a name that never resolves (a typo like
  `Bogus b;`) still parses silently and only fails at runtime
  ("makeValueForType called with unhandled type 0"). The post-parse
  forward-reference pass in parser.c (reaResolveForwardClassRefs) is the
  natural place to report "unknown type 'X'" at parse time — the blocker is
  that generic type parameters also appear as unresolved TYPE_UNKNOWN
  references there, so the pass would need to know which references sit
  inside a generic scope before it can complain about the rest.
- Class/function name-collision handling — FULLY RESOLVED (2026-08-11).
  Found while fixing the Aether-side constructor mis-dispatch (pscal-core
  18c8acc), which repaired the constructor half: `new Widget(5)` runs the real
  constructor in either declaration order. The call-site half landed the same
  day; the bare name now resolves to the free function while the constructor
  keeps its `Class.Class` identity, as proposed here. Three separate defects,
  all the same mistake — treating whatever occupies the shared bare name as
  this declaration's own:
  - parseStatement accepted `(` as a declarator opener after a type name, so
    `widget(w);` went to parseVarDecl, which consumed the name as a type,
    found no declarator, and returned an empty declaration group; the leftover
    `(w)` re-parsed as a parenthesized expression. That is where the silence
    came from, and where `widget(w, 9)`'s "Unexpected token COMMA" came from.
    Only `Type (*fp)(...)` still takes that route.
  - parseFunctionDecl's registration followed aliases, so a free function
    adopted its same-named class's constructor symbol and overwrote its type,
    type_def and arity. A VOID constructor recorded as returning Int made the
    VM pop a bogus return value after `new` — "Cannot assign INTEGER to
    POINTER". Only reproduced with the class declared first.
  - ensureConstructorAliasForClass overwrote a real free function's symbol,
    rewriting it into an alias for the constructor; it now declines on a
    non-alias entry, like pscal-core's ensureProcedureAlias.
  parseVarDecl no longer returns an empty declaration group at all: a type name
  with no declarator is a diagnostic, which closes the silence structurally for
  shapes nobody has hit yet. Pinned by tests/rea/class_function_name_collision*
  (constructor integrity, both call shapes, and a value-returning collision in
  both declaration orders).
  Lesson worth keeping: the bare name is a shared namespace, and every place
  that reads or writes it needs to ask *whose* it is. Three sites had to be
  taught the same rule; a fourth (pscal-core's `new` resolution) had already
  been taught it. When one of these turns up again, grep for the others.
