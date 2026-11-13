# zunit: volume and duration unit literals for dap and siggy

Promoted from `.mailbox/units-module/3.md`.

## Purpose and scope

`zunit` is a Zig module providing public unit types for [dap](https://github.com/sirkon/dap), the CLI argument parser, and
[siggy](https://github.com/sirkon/siggy), the config parser. Consumers write

```zig
.field = dap.Flag(zunit.Volume(.mib).Dap) { /* ... */ }
```

for command-line flags and arguments, and

```zig
cache: zunit.Duration(.secs).Siggy
```

for config leaves. `Volume` and `Duration` are comptime type factories parametrized by a base unit; each returned namespace
carries exactly two wrapper types, `Dap` and `Siggy`, over one private base type per unit kind. The module also contains a
private test submodule — the only place either SDK is imported.

Target Zig version is 0.17: `minimum_zig_version = "0.17.0"`, developed and verified with a local zig 0.17.1 toolchain
against dap v0.0.9 (commit 2abdabc) and siggy v0.0.1 (commit 9933fec), both declaring `minimum_zig_version = "0.17.0"`.

## Public surface

The package root exports exactly two factories and their base enums:

```zig
pub const VolumeBase = enum { b, kib, mib, gib, tib, pib, eib, zib, yib };
pub fn Volume(comptime base: VolumeBase) type;

pub const DurationBase = enum { nanosecs, microsecs, millisecs, secs, mins, hours };
pub fn Duration(comptime base: DurationBase) type;
```

The namespace returned by each factory has exactly two members, `Dap` and `Siggy`. Nothing else is public at the root; raw
storage is private, and construction goes through checked constructors (see "Wrapper contracts").

The parametrization means the decoded raw value must be a **multiple of the chosen base**: under `Volume(.mib)` both `2KiB`
(2048 bytes) and `4096` fail with a clear diagnostic.

## Value domains

- **Volume** is an unsigned byte count. Raw storage is `u128`; `value()` returns `u128`; `value64()` returns
  `error{ UnitOverflow }!u64`, because the `eib` and larger bases routinely exceed u64.
- **Duration** is a signed nanosecond count with Go `time.Duration` parity. Raw storage is `i64`; `value()` returns `i64`
  (±2^63 ns, roughly ±292 years). The two's-complement asymmetry carries over: `-9223372036854775808ns` (the i64 minimum)
  decodes, while `9223372036854775808ns` (+2^63 ns) overflows and is a value error.
- Zero is valid for both kinds under every base.
- The multiple-of-base check runs **after full evaluation**, on the final raw value: `1.5MiB` (1,572,864 bytes) decodes
  under `Volume(.b)` and `Volume(.kib)` and is rejected under `Volume(.mib)`; `1500ms` decodes under
  `Duration(.millisecs)` and is rejected under `Duration(.secs)`. For durations the check is sign-agnostic, evaluated on
  the signed total: `-120s` and `120s` are both whole minutes under `Duration(.mins)`, while `90s` and `-90s` are both 1.5
  minutes and both rejected.

## Dependency model

The public module is dependency-free. The `Dap` wrapper speaks pure `std` types, and the `Siggy` wrapper declares its
`node` and `diag` parameters as `anytype`, so siggy is never imported by the module; the gate and call-site constraints are
proven by the test submodule against the real SDKs. dap and siggy appear in `build.zig.zon` solely as dependencies of that
private test submodule, so a consumer that does not use siggy never wires it (and vice versa): a dap-only program does not
pull siggy into its dependency graph.

## Literal grammar

### Shared scanner

Both unit kinds share one scanner and one exact decimal engine:

- Input is consumed as exact ASCII bytes. Digits are `0-9`; leading zeros are tolerated (`007` = 7).
- A decimal point requires at least one digit on each side **and** a unit suffix: `1.MiB`, `.5MiB`, `1.5` and `1.h` are
  all grammar errors under both kinds — one scanner, one rule.
- No whitespace is tolerated anywhere; any byte outside the kind's alphabet is a stray character, so `"2 MiB"` fails in a
  quoted siggy value.
- Empty input is a grammar error.
- Digit strings that overflow the `u128` accumulator are rejected early; a 4096-byte siggy literal (`max_literal_len`)
  cannot wedge the parser.
- All arithmetic is exact checked integer math with a `u128` mantissa and a decimal scale — no floating point anywhere.
  `1.5MiB` computes as `15 × 2^20 / 10 = 1572864`, exactly.

### Volume literals

| tag   | factor | canonical suffix |
| ----- | ------ | ---------------- |
| `b`   | 2^0    | — (bare integer) |
| `kib` | 2^10   | `KiB`            |
| `mib` | 2^20   | `MiB`            |
| `gib` | 2^30   | `GiB`            |
| `tib` | 2^40   | `TiB`            |
| `pib` | 2^50   | `PiB`            |
| `eib` | 2^60   | `EiB`            |
| `zib` | 2^70   | `ZiB`            |
| `yib` | 2^80   | `YiB`            |

A volume literal is a magnitude — `digits`, or `digits . digits` — followed by an optional suffix. There is no sign: `-5`
and `+5` are stray-byte grammar errors. Without a suffix the magnitude must be a plain integer (the dot requires a suffix)
and denotes raw bytes. With a suffix, for prefix letter `X ∈ {K,M,G,T,P,E,Z,Y}`, exactly five spellings are accepted —
`XiB`, `Xib`, `Xi`, `xib`, `xi` (first letter case-insensitive, the `i` mandatory and lowercase, the optional trailing
`b`/`B` case-insensitive) — and the value is `magnitude × 2^(10·k)`. Everything else is rejected: `M`, `Mb`, `MIB`, `KIB`,
`KI`, `mIB` — marketing megabytes and their spellings are forbidden. There is no bare byte suffix.

Examples, for `Volume(.mib)` unless stated:

| input                                | verdict                                          |
| ------------------------------------ | ------------------------------------------------ |
| `2MiB`, `2Mib`, `2Mi`, `2mib`, `2mi` | ok, 2097152 — all five spellings                 |
| `2097152`                            | ok, 2097152                                      |
| `512KiB`, `4096`                     | error — not a multiple of 2^20                   |
| `2KiB` (under `Volume(.kib)`)        | ok, 2048                                         |
| `2TiB`                               | ok, 2199023255552                                |
| `1.5MiB` (under `Volume(.kib)`)      | ok, 1572864 = 1536 KiB exactly                   |
| `1.5MiB` (under `Volume(.mib)`)      | error — not a whole count of MiB                 |
| `0.0001MiB`                          | error — 104.8576 bytes is not a whole byte count |
| `1.5`                                | error — the dot requires a suffix                |
| `2MB`, `2M`                          | error — marketing spellings forbidden           |
| `0`                                  | ok — zero is a multiple of everything            |
| `-5`                                 | error — volume is unsigned                       |

### Duration literals

| tag         | factor (ns) | canonical suffix |
| ----------- | ----------- | ---------------- |
| `nanosecs`  | 1           | `ns`             |
| `microsecs` | 10^3        | `us`             |
| `millisecs` | 10^6        | `ms`             |
| `secs`      | 10^9        | `s`              |
| `mins`      | 60·10^9     | `m`              |
| `hours`     | 3600·10^9   | `h`              |

```text
duration   := [ sign ] component { component }
component  := digits [ "." digits ] [ suffix ]
suffix     := "ns" | "us" | "ms" | "s" | "m" | "h"
sign       := "-" | "+"
```

Constraints:

- The optional sign is a single `-` or `+` at the front of the whole literal, before all components; components themselves
  stay unsigned magnitudes. `-1h30m` is -(1h30m); `1h-30m`, `1h+30m` and `--5s` are grammar errors; `-0` and `+0` decode
  to zero.
- Suffixes are the six ASCII spellings above, case-sensitive. Go's non-ASCII microsecond spellings `µs` (U+00B5 micro
  sign) and `μs` (U+03BC Greek small mu) are rejected as stray bytes, and `encode` emits `us`. The charter's earlier
  `mks` spelling is dead.
- Components run strictly descending `h > m > s > ms > us > ns`, each unit at most once per literal.
- A suffixless component is legal only when it is the entire literal: `5` is 5 ns and `-30` is -30 ns, while `1h30` is a
  grammar error — silently reading it as 1 h + 30 ns would be a footgun where `1h30m` was meant. Zero-valued suffixed
  components are fine (`0h0m` decodes to 0).
- A fraction is allowed on any component, not only the last: `1h30.5m` and `1.5h` are both valid.
- No suffix means nanoseconds: `5` and `5ns` are the same value.

Every component contributes `mantissa × factor / 10^scale` nanoseconds, which must divide exactly: `0.5ns` is
grammatical but unsatisfiable — a value error under every base.

Examples, for `Duration(.secs)` unless stated:

| input                                 | verdict                                                   |
| ------------------------------------- | --------------------------------------------------------- |
| `500ms`                               | error — half a second is not a whole second               |
| `1500ms` (under `.millisecs`)         | ok, 1500000000 ns                                         |
| `1h30m`                               | ok, 5400000000000 ns                                      |
| `1.5h`                                | ok — same value as `1h30m`                                |
| `2h45m10s500ms` (under `.millisecs`)  | ok, 9910500000000 ns                                      |
| `90s` (under `.mins`)                 | error — 1.5 minutes                                       |
| `120s` (under `.mins`)                | ok, 2 minutes exactly                                     |
| `-120s` (under `.mins`)               | ok, -2 minutes exactly — the check is sign-agnostic       |
| `30m1h`                               | error — wrong order                                       |
| `1m30m`                               | error — repeated unit                                     |
| `1h30.5m`                             | ok — fraction on a non-final component                    |
| `1.5us` (under `.nanosecs`)           | ok, 1500 ns                                               |
| `1.5us` (under `.microsecs`)          | error — not a whole microsecond                           |
| `5`                                   | ok, 5 ns                                                  |
| `0`                                   | ok, 0 ns                                                  |
| `-30`                                 | ok, -30 ns — suffixless legal as the entire literal       |
| `1.5`                                 | error — the dot requires a suffix                         |
| `1.5ns`                               | error — grammatical, but 1.5 ns is not whole              |
| `-5s`                                 | ok, -5000000000 ns                                        |
| `-1h30m`                              | ok, -5400000000000 ns — the sign spans the whole          |
| `1h-30m`, `1h+30m`, `--5s`            | error — sign only at the front, single                    |
| `1h30`                                | error — suffixless component inside a combination         |
| `5mks`, `5µs`, `5μs`                  | error — `mks` is dead; non-ASCII spellings are stray bytes |
| `-9223372036854775808ns`              | ok — the i64 minimum                                      |
| `9223372036854775808ns`              | error — +2^63 ns overflows the domain                     |

## Evaluation pipeline

Both kinds run the same pipeline: scan the literal into `(mantissa: u128, decimal scale, unit factor)` → multiply with
overflow checks → divide by `10^scale`, requiring exact divisibility → sum the components with overflow checks (duration
only) → check the domain → apply the sign last (duration only) → check the total is a multiple of the base factor via
remainder → check it fits the raw domain.

For durations the domain check is: magnitude ≤ 2^63 - 1, or exactly 2^63 when the literal is negative — the i64 minimum
is reachable only through a negative literal. Volume is the same engine without the sign, over `u128`.

Inexact decimals are value errors under every base: `0.5ns` is not a whole nanosecond, and `0.0001MiB` is 104.8576 bytes,
not a whole byte count.

## Canonical encoding

`encode` writes the value in base units with the base's canonical suffix. `Duration(.nanosecs)` always writes the explicit
`ns`, so canonical duration encodings are never bare numbers; `Volume(.b)` alone encodes bare digits, since no byte suffix
exists. Negative durations prefix `-`; zero encodes as `0` with the base's suffix.

| unit                   | raw value     | encodes as |
| ---------------------- | ------------- | ---------- |
| `Volume(.mib)`         | 2097152       | `2MiB`     |
| `Volume(.b)`           | 2097152       | `2097152`  |
| `Volume(.mib)`         | 0             | `0MiB`     |
| `Duration(.mins)`      | 120000000000  | `2m`       |
| `Duration(.mins)`      | -120000000000 | `-2m`      |
| `Duration(.nanosecs)`  | 5             | `5ns`      |
| `Duration(.microsecs)` | 5000          | `5us`      |
| `Duration(.secs)`      | 0             | `0s`       |

Every canonical form re-decodes to the identical value under the same base. The round-trip is not decoration: dap renders
`.direct` defaults in help text and round-trips them through `encode` → `decode` at runtime, and siggy's `stringify`
writes the encoded text back into configs.

## Wrapper contracts

Both wrappers hold one private raw value — `u128` for Volume, `i64` for Duration — and delegate all parsing and encoding
to the shared private base. The public surface of each wrapper is exactly what follows; nothing else ships in v1 (no
`std.fmt` integration, no aliases, no additional unit kinds).

The Volume wrappers — the namespace returned by `zunit.Volume(base)`; `Siggy` mirrors the identical value surface:

```zig
pub const Dap = struct {
    pub fn decode(allocator: std.mem.Allocator, data: []const u8) error{ InvalidWire, InvalidValue }!Dap;
    pub fn encode(self: *const Dap, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8;
    pub fn deinit(self: *Dap, allocator: std.mem.Allocator) void;
    pub fn value(self: Dap) u128;
    pub fn value64(self: Dap) error{ UnitOverflow }!u64;
    pub fn fromBase(n: u128) error{ UnitOverflow }!Dap;
    pub fn fromBytes(raw: u128) error{ NotMultipleOfBase }!Dap;
};
```

The Duration wrappers — `Siggy` mirrors, minus `value64`:

```zig
pub const Dap = struct {
    pub fn decode(allocator: std.mem.Allocator, data: []const u8) error{ InvalidWire, InvalidValue }!Dap;
    pub fn encode(self: *const Dap, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8;
    pub fn deinit(self: *Dap, allocator: std.mem.Allocator) void;
    pub fn value(self: Dap) i64;
    pub fn fromBase(n: i64) error{ UnitOverflow }!Dap;
    pub fn fromNanos(raw: i64) error{ NotMultipleOfBase }!Dap;
};
```

- `fromBase(n)` takes a count of base units — `zunit.Volume(.mib).Dap.fromBase(2)`; for durations it computes a checked
  `n × factor` in `i128`. It can fail only on overflow: a count of base units is a multiple by construction.
- `fromBytes(raw)` / `fromNanos(raw)` take absolute raw values and can fail only on the multiple check; neither can
  overflow, since the input already is the domain.

The `Siggy` wrapper — identical value surface, siggy-shaped service methods:

```zig
pub const Siggy = struct {
    pub fn decode(
        self: *Siggy,
        source_arena: std.mem.Allocator,
        value_arena: std.mem.Allocator,
        node: anytype,
        diag: anytype,
    ) anyerror!void;
    pub fn encode(self: *const Siggy, allocator: std.mem.Allocator) anyerror![]const u8;
};
```

- `node` and `diag` are `anytype`: siggy is never imported by the module. They are siggy's `AstNode` and
  `*siggy.Diagnostic` at every call site, and the test submodule proves it against the real SDK.
- `decode` accepts `.literal` and `.quoted` nodes, running the identical grammar on the text: `cache = 2MiB` and
  `cache = "2MiB"` both decode. It rejects `.block` and `.tagged` (including `2MiB { }`) with
  `diag.code = error.UnsupportedShape` and a message naming the expected shape.
- Grammar and value failures set `diag.code = error.Custom` with a precise message — e.g. `512KiB is not a whole number
  of mebibytes` — leave `diag.offset` exactly as siggy pre-filled it, and return the same error as the code written, so
  siggy's classification is the identity. The message is formatted into `source_arena` (scratch), following siggy's own
  `CoresMask` pattern; siggy persists the surviving diagnostic into the value arena itself.
- siggy pre-allocates `Self` in the value arena; `decode` only fills the integer and allocates nothing on success.
- In configs, an optional unit field (`?zunit.Volume(.mib).Siggy`) follows normal siggy optionality: `k = { }` yields
  `null` before this decoder is ever consulted.

### Error split

| failure class | dap error      | siggy diagnostic                   |
| ------------- | -------------- | ---------------------------------- |
| grammar       | `InvalidWire`  | `error.Custom` + message           |
| value         | `InvalidValue` | `error.Custom` + message           |
| node shape    | —              | `error.UnsupportedShape` + message |

Grammar failures are bad or unknown suffixes, stray bytes or whitespace, empty input, a misplaced or repeated sign,
wrong component order, or a suffixless component inside a combination. Value failures are inexact decimals, values that
are not a multiple of the base after evaluation, and domain overflow. Node-shape failures are siggy-only: `.block` and
`.tagged` arrive with no automatic unwrapping and are refused.

dap's documented semantics: `InvalidWire` — the token is not the right shape; `InvalidValue` — shape is fine, value
rejected.

### Allocation profile

Decode paths and constructors allocate nothing — the value is one integer. The only allocations anywhere are
contractual: `encode` prints into the provided allocator, and a failing siggy `decode` formats its message into
`source_arena`.

## dap integration constraints

Verified against dap v0.0.9 (commit 2abdabc, `minimum_zig_version = "0.17.0"`); names refer to `src/dap.zig`:

- The custom-value gate is presence-only: `isDecodable` checks
  `@hasDecl(T, "decode") and @hasDecl(T, "encode") and @hasDecl(T, "deinit")`. No dap type appears in any required
  signature — dap does not need to be imported to satisfy dap.
- The operative constraint is the call site: `decodeInto` runs `out.* = try T.decode(allocator, data)` inside a function
  whose error set is `DecodeError || std.mem.Allocator.Error`, and `DecodeError` is exactly
  `std.mem.Allocator.Error || error{ InvalidWire, InvalidValue }` — the wrapper's `error{ InvalidWire, InvalidValue }`
  is a subset.
- `decode` is a static constructor returning a fully built value.
- dap round-trips every `.direct` default at runtime through `tmp.encode(allocator)` → `T.decode(allocator, wire)` and
  frees the wire itself (`assignDirectDefault`): `decode` must re-accept exactly what `encode` emits. This is what
  forces the sign grammar on durations — once `encode` can emit `-2h`, `decode` must take it back.
- Defaults are rendered in help text through `encode` as well.
- dap calls `val.deinit(allocator)` (`deinitValue`); for a type holding one integer, `deinit` is an empty body that must
  still exist.
- A `.direct` default authors as `dap.defaultValue(V, V.fromBase(2) catch unreachable)` — comptime-checked; a negative
  duration default with `fromBase(-2)` — and dap round-trips it at runtime.
- `encode` is invoked on a `var` (auto-ref), so the shared spelling `encode(self: *const Self, allocator)` serves both
  SDKs.

## siggy integration constraints

Verified against siggy v0.0.1 (commit 9933fec, `minimum_zig_version = "0.17.0"`):

- The custom-leaf gate (`isCustom`, `src/siggy/support.zig`): a struct declaring `decode` and `encode`, where `decode`'s
  first parameter is exactly `*T` with at least two parameters total, and `encode`'s first parameter is exactly `T` or
  `*const T`. A mutable `*T` self on `encode` is not recognized.
- The call is `T.decode(self_ptr, source_arena, value_arena, node, &diag)` (`src/siggy/schema.zig`); siggy pre-allocates
  `Self` in the value arena. `source_arena` is scratch; the surviving diagnostic is persisted into the value arena by
  siggy itself, so a failure message may live in scratch.
- `AstNode` (`src/siggy/ast.zig`) is `union(enum) { literal: []const u8, quoted: []const u8, block: *Block, tagged:
  Tagged }` and carries no offset — the offset arrives pre-filled in `diag.offset`, and the wrapper must not touch it.
- On error from a custom `decode`, siggy keeps the `diag.code` and `diag.message` set by the wrapper (substituting
  `@errorName(err)` only when the message is empty) and surfaces `classify(diag.code)`, the identity for every
  `ParsingError` member; both `UnsupportedShape` and `Custom` are members (`src/diagnostic.zig`).
- The encoder inspects `encode`'s first parameter and calls `T.encode(&value, alloc)` for a `*const T` self
  (`encodeCustom`, `src/siggy/schema.zig`) — the by-pointer branch the shared spelling targets.
- siggy resolves optionality before consulting a custom decoder: `k = { }` for a `?zunit.Volume(.mib).Siggy` field
  yields `null` and the wrapper's `decode` never runs.

## Module layout, build and pinning

```text
src/
  root.zig          # pub Volume, pub Duration; nothing else public
  unit/
    core.zig        # shared literal scanner + exact decimal engine (checked integer math, no floats)
    volume.zig      # volume base type + suffix table + Dap/Siggy wrappers
    duration.zig    # duration base type + suffix/combination engine + wrappers
  tests/            # private test submodule — the only dap/siggy importers
    root.zig        # relatively imports ../unit internals; imports dap and siggy as modules
    core.zig, volume_dap.zig, volume_siggy.zig, duration_dap.zig, duration_siggy.zig
```

- `build.zig` exposes the public module — `addModule("zunit", …)`, rooted at `src/root.zig`, with no dap or siggy
  imports — and wires dap and siggy as modules only into the `zig build test` target.
- `build.zig.zon` declares `.name = .zunit` and `minimum_zig_version = "0.17.0"`, and pins `dap` v0.0.9 and `siggy`
  v0.0.1 by git-tarball url+hash; both tags exist in the local checkouts, and dap v0.0.9 carries the Zig 0.17 fix.
  Development may use local path dependencies instead; the shipped `build.zig.zon` pins tarballs.
- The repository directory and README may be renamed from `zuinit` to match the package name; that is cosmetic and does
  not block implementation.

## Test submodule obligations

- every accepted suffix spelling for every base, and the canonical rejections: `M`, `Mb`, `MIB`, `KIB`, `KI`, `mIB`,
  plus `mks` (dead) and `µs`/`μs` (rejected as stray bytes);
- the factor requirement, including `2KiB` and `4096` under `Volume(.mib)`, and the decimal interplay: `1.5MiB` decodes
  under `.b`/`.kib` and is rejected under `.mib`;
- decimal exactness: `1.5MiB` = 1572864, `2.0KiB`, `0.0001MiB` rejected under every base, `0.5ns` rejected under every
  duration base;
- domain edges: `0` everywhere; volume overflow of `u128`; duration at the i64 minimum accepted and one nanosecond beyond
  it in either direction rejected; overlong literals rejected early;
- sign handling: `-1h30m`, `-0`, `+0`, mid-literal signs rejected, negative values round-tripping through canonical
  encodings;
- combinations: strict descending order, no repeats, fractions on any component, the suffixless-in-combination rule
  (`1h30` is an error), and `us` everywhere `mks` used to be;
- canonical encoding: base-derivation form for every base, explicit `ns` for `.nanosecs`, `-` prefix for negatives, and
  every encoding re-decoding to the identical value;
- dap: flag and argument decode, `.direct` defaults authored via `fromBase` — positive and negative — and round-tripped
  by dap's own machinery, `encode` output in help text, the `deinit` path, and both error codes surfaced as documented;
- siggy: literal and quoted decode, block/tagged rejection, `stringify` round-trip including negative values, rendered
  diagnostics for each failure class (message present, `offset` untouched), and the value-survives-source-arena-reset
  discipline;
- the raw engine directly, via relative imports from inside the module.

## Where this design supersedes PLAN.md

PLAN.md is the charter; this document is normative wherever the correspondence moved past its prose:

- the microsecond suffix is `us`, not PLAN's `mks`;
- the Duration domain is signed `i64` nanoseconds with `value() i64`, not PLAN's `value() u64`;
- the 2^40 volume base tag is `tib`, not PLAN's `tip`;
- the package and module name is `zunit` — `zuinit` in the repository name is a typo;
- the requirement is "multiple of the base", not PLAN's word "factor" — PLAN's own `2KiB`/`4096` examples already meant
  multiple.
