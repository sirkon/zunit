# AGENTS.md

`zunit` is a small dependency-free Zig module exposing unit-literal types for
[dap](https://github.com/sirkon/dap) (CLI flags) and
[siggy](https://github.com/sirkon/siggy) (config files). It is a library, not an
executable: there is no `main`, no install step, and no deployment target.

## Commands

```sh
zig build test          # the only build step that exists
zig build test --summary all
zig fmt .               # Zig formatter; the repository is zig-fmt clean
```

- `zig build` alone is a no-op: `build.zig` defines only the `test` step and
  the public module, with no install artifact. Always run `zig build test`.
- Minimum Zig is `0.17.0` (`build.zig.zon`); development is verified with
  0.17.1. Both pinned dependencies also require 0.17.
- There is no CI, no lint config, no Makefile, and no package manager config.
- `.prettierrc` (`printWidth: 120`, `proseWrap: always`) is for Markdown only;
  there is no `package.json`, so prettier is not installed by the repo.

## Architecture

```
src/root.zig           public surface only: VolumeBase, DurationBase,
                       Volume(comptime base), Duration(comptime base)
src/unit/core.zig      shared literal scanner + exact decimal engine
src/unit/volume.zig    VolumeBase, suffixes, factor table, Namespace(base)
src/unit/duration.zig  DurationBase, suffixes, factor table, Namespace(base)
src/tests.zig          test entry point -> src/tests/root.zig
src/tests/*.zig        SDK integration tests (dap/siggy), engine + surface tests
```

Data flow: a namespace type returned by `Volume(base)`/`Duration(base)` has
exactly two members, `Dap` and `Siggy`. Both are thin integer wrappers
(`u128` bytes / `i64` nanoseconds) that delegate parsing and encoding to their
per-kind module, which delegates token scanning and exact decimal arithmetic to
`core.zig`. `root.zig` imports the two unit modules; nothing else is public.

### Layering rule

The public module must never import `dap` or `siggy`. `Dap` methods use only
`std`; `Siggy.decode` declares `node` and `diag` as `anytype`. The SDKs are
imported exclusively by `src/tests/`, and `build.zig` attaches them only to the
integration-test artifact. Do not add SDK imports to `src/unit/` or
`src/root.zig`, and do not add them to the module definition in `build.zig`.

## Writing tests

There are two test artifacts, both run by `zig build test`:

1. `src/tests.zig` -> `src/tests/root.zig`, with `dap` and `siggy` modules
   attached. This is the only place SDK-level tests belong.
2. `src/root.zig` as a module test, which reaches the inline `test` blocks in
   `src/unit/core.zig`.

**A new file under `src/tests/` does not run until it is added to
`src/tests/root.zig`.** Engine/unit tests may also go inline in `src/unit/*.zig`;
SDK tests cannot, because those files must not import the SDKs.

Patterns used by existing tests:

- Allocation: `std.testing.allocator` in dap/engine tests.
- siggy: create a table type `const Config = struct { ... }` and
  `siggy.parser(Config)` at file scope, then `var p: Parser = undefined;
  p.init(allocator, value_arena.allocator(), silentPrinter)`. Use an
  `ArenaAllocator` for values and a `silentPrinter` that ignores diagnostics;
  diagnostics are asserted through `p.diagnostic.?.code/message/offset`.
- dap: define the declaration struct and `dap.generate(...)` at file scope so
  the comptime parser is built once, then parse, inspect help data, and call
  `CLI.deinit`.
- `inline for` over base enums is the norm for per-base coverage. Tables of
  `{ base, raw, text }` cases drive canonical-encoding round trips.
- Diagnostics messages are asserted verbatim, including quoted input. Changing
  a message in `core.fail` breaks tests; update both together.

## Conventions and non-obvious behavior

- Formatting is `zig fmt`; 4-space indent, file names lowercase snake_case.
  Test files are named `<kind>_<sdk>.zig`.
- The base parameter means the decoded raw value must be a **whole multiple of
  the selected base**. The check runs on the final raw value after the whole
  literal is evaluated, not per component. Under `Volume(.mib)`, `512KiB` and
  `1.5MiB` fail; under `Volume(.kib)` the latter succeeds.
- All arithmetic is checked `u128` integer math with a decimal scale; there is
  no floating point. `core.scaleToInteger` must divide exactly or return
  `error.Inexact`. Very large scales are handled without computing `10^scale`.
- Errors are split by class and this split is part of the API:
  - grammar -> `InvalidWire` (dap) / `error.Custom` + message (siggy)
  - value (inexact, not a multiple, out of domain) -> `InvalidValue` /
    `error.Custom` + message
  - wrapper constructors use `UnitOverflow` and `NotMultipleOfBase`
  - siggy block/tagged nodes -> `UnsupportedShape` + message
- Siggy `decode` must not touch `diag.offset` (siggy pre-fills it) and must
  format messages into `source_arena`. `encode` must take `*const Self`;
  siggy only recognizes an immutable or pointer-const `encode` self.
- dap requires `decode`, `encode`, and `deinit` to exist. Volume wrappers add
  `value64`; duration wrappers add `fromNanos`. Do not add `value64` to
  duration or `deinit` to `Siggy`: `src/tests/core.zig` asserts the exact
  surface with `@hasDecl`.
- `encode` must emit a canonical form that `decode` accepts back. dap
  round-trips `.direct` defaults through encode/decode at runtime, so a
  one-way spelling is a bug. Volume `.b` encodes bare digits; durations always
  carry a suffix, including `ns`; negatives get a leading `-`.
- Duration literals accept one optional leading sign for the whole literal and
  components in strictly descending order (`h > m > s > ms > us > ns`), each
  unit at most once. A suffixless component is legal only as the entire
  literal (`1h30` is an error, not 1h + 30ns).
- Volume suffixes accept exactly `XiB`, `Xib`, `Xi`, `xib`, `xi`; marketing
  forms (`MB`, `M`, `MIB`) are deliberately rejected and test-covered.
- Design decisions that look like typos are intentional (see the final section
  of `designs/units-module.md`): the microsecond suffix is `us` (not `mks`),
  the 2^40 base tag is `tib` (not `tip`), and durations are signed `i64`
  nanoseconds (not `u64`).
- Each `unit/*.zig` file aliases `const Self = @This()` at the top and reuses
  `Self.factor`, `Self.encode`, etc. inside `Namespace`, which is how the
  returned type reaches the file-scope helpers.

## Reference material

- `designs/units-module.md` is the normative specification: grammar tables,
  example verdicts, wrapper contracts, SDK integration constraints, and the
  test obligations. Read it before changing parsing behavior.
- `.contexts/DAP-SDK.md` and `.contexts/SIGGY-SDK.md` are captured SDK
  references for the pinned versions. They describe the libraries themselves;
  the design document and the tests are authoritative for how `zunit` uses
  them.
- `.contexts/MAILBOX.md` defines the mailbox design protocol used in this repo:
  `.mailbox/<subject>/<N>.md` letters are append-only, a human fills the
  `# Pad`, and a finished thread is compiled (not copied) into
  `designs/<subject>.md`, which stays as history.
- Dependencies are pinned by tarball URL + hash in `build.zig.zon` (dap
  v0.0.9, siggy v0.0.1). Changing a version requires updating its hash; do not
  switch to path dependencies in the committed file.
