# zunit

Volume and duration unit literals for [dap](https://github.com/sirkon/dap) and
[siggy](https://github.com/sirkon/siggy).

```zig
.cache = dap.Flag(zunit.Volume(.mib).Dap){ .help = "Cache size." },
```

```zig
expire: zunit.Duration(.secs).Siggy,
```

Values must be whole multiples of the selected base: `2MiB`, `2048KiB`, or
`2097152` under `Volume(.mib)`, and `1h30m` or `5400s` under `Duration(.secs)`.
