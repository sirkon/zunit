# zunit

Volume and duration literals for [dap](https://github.com/sirkon/dap) and
[siggy](https://github.com/sirkon/siggy).

Instead of parsing sizes and timeouts by hand, declare the unit each option is expressed in and let the user write
`2MiB` or `1h30m`:

```zig
const dap = @import("dap");
const siggy = @import("siggy");
const zunit = @import("zunit");

const Cache = zunit.Volume(.mib);
const Timeout = zunit.Duration(.secs);

const Config = struct {
    cache: Cache.Siggy,
    timeout: ?Timeout.Siggy = null,
};

const Parser = siggy.parser(Config);

const Def = .{
    .cache = dap.Flag(Cache.Dap){
        .default = dap.defaultValue(Cache.Dap, Cache.Dap.fromBase(2) catch unreachable),
        .help = "Cache size.",
    },
    .timeout = dap.Flag(Timeout.Dap){ .help = "Timeout." },
};
```

The same declarations accept these spellings:

```ini
cache = 2MiB
timeout = 1h30m
```

Here `cache` is 2,097,152 bytes and `timeout` is 5,400,000,000,000 nanoseconds. Volumes understand binary suffixes from
`KiB` through `YiB`, and durations understand `h`, `m`, `s`, `ms`, `us`, and `ns`, including combinations and a leading
sign.

The base you choose is also the precision you accept: `2048KiB`, `2MiB`, and `2097152` all fit under `Volume(.mib)`,
while `512KiB` does not, and `Duration(.secs)` takes `1h30m` but not `500ms`.

## Adding it

```sh
zig fetch --save=zunit git+https://github.com/sirkon/zunit.git#<commit-or-tag>
```

```zig
const zunit = b.dependency("zunit", .{ .target = target, .optimize = optimize }).module("zunit");
exe.root_module.addImport("zunit", zunit);
```

`zunit` requires Zig 0.17 or newer, and the module itself imports only `std`.

The full grammar, wrapper API, encoding rules, and error behavior are documented in [AGENTS-SDK.md](AGENTS-SDK.md).
