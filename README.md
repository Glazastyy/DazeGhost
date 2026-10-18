# DazeGhost

DazeGhost is a Lua 5.4 minifier and obfuscator with a C++17 command-line interface. The pipeline is lexer, parser, lexical binding, transformation, emission, sealing, and optional final packing.

## Requirements

- Lua 5.4
- CMake 3.16 or newer
- A C++17 compiler
- Network access during the first CMake configuration when no compatible system Lua 5.4 is available

The build first looks for a matching system Lua 5.4 installation. If it is unavailable, CMake downloads the pinned official Lua 5.4 source, verifies its SHA-256 hash, and builds it privately as a static library. A custom compatible installation can be selected with `-DDAZEGHOST_LUA_INCLUDE_DIR=/path/include -DDAZEGHOST_LUA_LIBRARY=/path/lib/liblua5.4.so`.

## Build

```bash
cmake -B build -S .
cmake --build build
```

The executable is generated at the project root as `./dazeghost`. It locates Lua modules next to the executable, one directory above it, through `DAZEGHOST_ROOT`, or from the current directory.

## Usage

```bash
./dazeghost --minify -o minified.lua script.lua
./dazeghost --obfuscate --anti-ia -i script.lua -d caos.lua -o protected.lua
./dazeghost --obfuscate --anti-ia --rounds 5 --density 70 --compress -i script.lua -d caos.lua -o protected.lua
```

Use `--help` for the complete option list. The C++ executable is the supported command-line entry point; no Lua generator script is required.

## Obfuscation

The obfuscator renames eligible locals, encodes string literals, applies conservative control-flow transformations, mixes optional decoy fragments, and seals each round with a keyed ARX stream mixer, shuffled blocks, multiple runtime dispatchers, and an integrity check.

The loader splits key material into shares and reconstructs it at runtime. This is obfuscation, not secret storage. A self-contained loader cannot hide a secret from an analyst who can execute it. Sensitive decisions and secrets must remain server-side.

The `--anti-ia` mode adds inactive structural decoys. The decoy source is parsed but never executed during generation.

Builds without `--seed` use fresh 128-bit operating-system entropy. This changes the actual layout and runtime material, not only the output hash. Supplying `--seed` enables reproducible builds.

## Rounds and memory

Rounds are limited to 1 through 5. Later rounds use larger data blocks and less sealing noise by default to control growth while preserving independent randomization.

The C++ CLI passes each round through the staged obfuscation API. The current round is the only round retained by the transformation pipeline; the parser, Lua compiler, and sealing stage still require the current source as a complete string.

`--max-output-bytes` defaults to 12 MiB. `--max-intermediate-bytes` defaults to the larger of eight times that limit and 64 MiB. Both limits fail closed before an uncontrolled output is produced.

## Final packing

`--compress` applies the final LZ-style packer after obfuscation. The packed bytes are embedded directly as an escaped Lua binary literal; the output does not use Base64. The generated single-file loader validates an FNV-1a integrity checksum, decompresses the stream with overlap-safe back references, loads the recovered Lua chunk, and executes it.

The packed loader replaces the original output only when it is smaller. This prevents a compression request from increasing the artifact because of loader overhead.

The library interfaces are:

```lua
local minify = require("src.minify")
local obfuscate = require("src.obfuscate")
local compress = require("src.compress")

local compact = minify.minify(source)
local protected = obfuscate.obfuscate(source, {
    anti_ia = true,
    decoy_src = "caos.lua",
    rounds = 3,
    decoy_density = 70,
    mode = "bytecode",
    runtime = "auto"
})
local single_file = compress.wrap(protected)
```

## Tests

```bash
lua5.4 tests/test.lua
lua5.4 tests/regression.lua
lua5.4 tests/property.lua
lua5.4 tests/rounds.lua
lua5.4 tests/text.lua
lua5.4 tests/runtime.lua
lua5.4 tests/seed.lua
lua5.4 tests/compress.lua
lua5.4 tests/cli/run.lua
```

## Limitations

DazeGhost does not provide complete Lua virtual-machine virtualization, anti-debugging, or cryptographic secrecy. The runtime eventually reconstructs the payload and passes it to `load`. Inactive decoys can be removed by dynamic analysis, and the integrity checksum is not an authenticated signature. Evaluate the protection against the actual reverse-engineering threat model and runtime environment.

## License

MIT
