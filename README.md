# DazeGhost

DazeGhost is a Lua 5.4 source transformer, minifier, obfuscator, and single-file packer. The supported command-line interface is a C++17 executable that embeds Lua 5.4 and loads the transformation engine from this repository.

This project provides distribution hardening and raises the cost of casual inspection. It is not a server-side authorization system, a hardware security boundary, or a guarantee of secrecy against the owner of the execution machine.

## Requirements and build

The normal build requires CMake 3.16 or newer, a C++17 compiler, OpenSSL Crypto development files, and network access during the first configure when a compatible system Lua 5.4 installation is unavailable.

Native executables are stripped of symbol tables and built with native hardening flags by default. Set `-DDAZEGHOST_STRIP_SYMBOLS=OFF` or `-DDAZEGHOST_HARDEN_NATIVE=OFF` when debugging the C++ loader or generator.

Lua development headers and a system library are optional. CMake first checks for a matching system Lua 5.4 installation. If none is available, it downloads the pinned official Lua 5.4 source, verifies its SHA-256 hash, and builds Lua privately as a static library. This prevents incompatible Lua headers and libraries from being combined.

```bash
cmake -B build -S .
cmake --build build
./dazeghost --help
```

The executables are written to the project root: `./dazeghost` is the generator and `./dazeghost-loader` is the native loader template. The `build/` directory contains intermediate files and the root executables are ignored by Git.

To force the bundled Lua build:

```bash
cmake -B build -S . -DDAZEGHOST_USE_SYSTEM_LUA=OFF
cmake --build build
```

To select a compatible custom Lua 5.4 installation:

```bash
cmake -B build -S . \
  -DDAZEGHOST_LUA_INCLUDE_DIR=/path/to/lua/include \
  -DDAZEGHOST_LUA_LIBRARY=/path/to/lua/lib/liblua5.4.so
cmake --build build
```

The include directory and library must come from the same Lua 5.4 installation. Lua 5.5 headers cannot be combined with a Lua 5.4 library.

## Command-line interface

```text
./dazeghost [options] file.lua
```

The default operation is obfuscation. A positional input file or `--input` may be used. Progress messages are written to standard error, so generated Lua written to standard output remains valid.

Examples:

```bash
./dazeghost --minify -i script.lua -o minified.lua
./dazeghost --obfuscate --anti-ia -i script.lua -d caos.lua -o protected.lua
./dazeghost --obfuscate --rounds 3 --density 70 --compress \
  -i script.lua -d caos.lua -o protected.lua
./dazeghost --obfuscate --mode text --secret --native-loader \
  -i script.lua -o protected
```

Run `./dazeghost --help` for the compact built-in help.

## Complete option reference

### Operation, input, and output

| Option                | Default          | Description                                                                |
| --------------------- | ---------------- | -------------------------------------------------------------------------- |
| `--minify`            | Obfuscation      | Parses Lua 5.4 and emits compact equivalent source.                        |
| `--obfuscate`         | Enabled          | Runs transformation, sealing, and loader generation.                       |
| `--anti-ia`           | Disabled         | Adds inactive structural decoy material.                                   |
| `-i`, `--input FILE`  | Positional input | Reads the complete Lua source from `FILE`.                                 |
| `-d`, `--decoy FILE`  | `caos.lua`       | Reads decoy Lua source. It is parsed but never executed during generation. |
| `-o`, `--output FILE` | Standard output  | Writes the generated Lua artifact to `FILE`.                               |

If both `--minify` and `--obfuscate` are supplied, the last operation-selection option wins.

### Transformation and sealing

| Option                        | Default    | Valid range                        | Description                                                                                                                  |
| ----------------------------- | ---------- | ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `--rounds N`                  | `1`        | `1` to `5`                         | Complete sealing rounds. Size and generation cost grow substantially with each round.                                        |
| `--density N`                 | `100`      | `1` to `100`                       | Percentage of eligible decoy insertion points receiving decoy material.                                                      |
| `--mode VALUE`                | `bytecode` | `bytecode`, `text`                 | Stores compiled bytecode or transformed source. Bytecode is usually smaller but less portable.                               |
| `--runtime VALUE`             | `auto`     | `auto`, `linear`, `state`, `table` | Selects the generated dispatcher. `auto` diversifies the dispatcher per build.                                               |
| `--preset VALUE`              | `balanced` | `compact`, `balanced`, `strong`    | Applies a tested transformation profile. Explicit options always override the preset.                                        |
| `--name-generator VALUE`      | `random`   | `random`, `compact`, `mangled`     | Selects the generator used for local and generated identifiers.                                                              |
| `--min-chunk-size N`          | Adaptive   | `1` to `4096`                      | Minimum encrypted data-block size.                                                                                           |
| `--max-chunk-size N`          | Adaptive   | `1` to `4096`                      | Maximum encrypted data-block size. It must not be smaller than the minimum.                                                  |
| `--noise-density N`           | `25`       | `0` to `100`                       | Percentage of sealing instructions that receive a noise instruction. Later rounds use a lower adaptive default when omitted. |
| `--no-mix-original`           | Disabled   | Flag                               | Excludes original-source fragments from later decoy rounds.                                                                  |
| `--no-flatten`                | Disabled   | Flag                               | Disables conservative control-flow flattening.                                                                               |
| `--no-encode-strings`         | Disabled   | Flag                               | Keeps string literals in emitted form.                                                                                       |
| `--no-split-strings`          | Disabled   | Flag                               | Disables AST string fragmentation before string sealing.                                                                     |
| `--no-numbers-to-expressions` | Disabled   | Flag                               | Disables equivalent expressions for eligible integer literals.                                                               |
| `--no-constant-array`         | Disabled   | Flag                               | Disables the generated indirect constant pool.                                                                               |
| `--no-proxify-locals`         | Disabled   | Flag                               | Disables proxy indirection for ordinary locals and local functions. Loop and attributed locals remain native.                |
| `--anti-tamper`               | Disabled   | Flag                               | Adds a best-effort runtime hook check and may reject debuggers or profilers.                                                 |
| `--watermark TEXT`            | Disabled   | Text                               | Adds an encoded runtime watermark check. It is not a cryptographic signature.                                                |
| `-h`, `--help`                | Disabled   | Flag                               | Prints the command-line summary and exits.                                                                                   |

### Reproducibility, limits, and packing

| Option                       | Default                     | Description                                                                                                                               |
| ---------------------------- | --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `--seed N`                   | Fresh entropy               | Uses an integer seed for reproducible generation. Without it, fresh 128-bit operating-system entropy is used.                             |
| `--max-output-bytes N`       | `12582912`                  | Maximum output of every sealing round. The operation fails when exceeded.                                                                 |
| `--max-intermediate-bytes N` | `max(8 * output, 67108864)` | Maximum transformed intermediate source size.                                                                                             |
| `--compress`                 | Disabled                    | Runs the final LZ-style packer and keeps its loader only when it is smaller.                                                              |
| `--native-loader`            | Disabled                    | Embeds the final protected Lua payload into the native `dazeghost-loader` executable. Requires `--obfuscate`, `--secret`, and `--output`. |
| `--separate-vm FILE`         | Disabled                    | Writes the protected artifact to `--output` and creates an adjacent native VM bound to that exact artifact. Requires `--obfuscate` and `--output`. |

### Runtime secret

| Option               | Default                | Description                                                             |
| -------------------- | ---------------------- | ----------------------------------------------------------------------- |
| `--secret VALUE`     | Disabled               | Enables runtime password protection using `VALUE`. It is never printed. |
| `--secret=VALUE`     | Disabled               | Equivalent form that avoids ambiguity with positional arguments.        |
| `--secret`           | Disabled               | Generates a fresh secret and saves it to `dazeghost.secret.txt`.        |
| `--secret-file FILE` | `dazeghost.secret.txt` | Destination for a generated secret.                                     |

For explicit secrets, prefer `--secret=VALUE` or use `--input`, because an optional argument is ambiguous with a positional input path.

## Common workflows

### Minification

```bash
./dazeghost --minify --input script.lua --output minified.lua
```

Minification does not encrypt, seal, pack, or prompt for a password.

### Decoy-assisted obfuscation

```bash
./dazeghost --obfuscate --anti-ia \
  --input script.lua \
  --decoy caos.lua \
  --rounds 3 \
  --density 70 \
  --output protected.lua
```

The decoy file is parsed as data and never executed during generation.

### AST transformation pipeline

The default pipeline runs `split_strings`, `numbers_to_expressions`, `constant_array`, `proxify_locals`, and the optional `watermark` stage before local renaming, string encoding, and control-flow flattening. Each stage can be disabled independently with its CLI flag.

Local and generated identifiers use random legal Lua names with variable length and mixed case. The default build obtains fresh 128-bit operating-system entropy, so repeated builds with identical inputs produce different names and different transformation layouts. Supplying `--seed` intentionally makes the identifier sequence and the complete artifact reproducible.

The pipeline exposes three built-in profiles. `compact` prioritizes size and runtime cost, `balanced` enables the normal transformation set, and `strong` enables the normal set plus best-effort runtime hook checks. These profiles are configuration bundles, not security ratings. Explicit options take precedence over profile values.

Library callers can replace the default list with `steps`. Each custom stage receives `(ast, context)` and may mutate the AST in place. The context exposes `options`, `rand`, and `freshName()`.

Stages can also be registered at runtime:

```lua
local pipeline = require("src.pipeline")

pipeline.register("custom_stage", function(ast, context)
    context.options.custom_stage_used = true
end)

local protected = obfuscate.transform(source, {
    steps = { "custom_stage", "constant_array" }
})
```

Name generators are independently replaceable through the `name_generator` option. Custom generators receive the per-build random source and the set of already-used identifiers. Returned values are validated as Lua identifiers and duplicate names are rejected.

```lua
local protected = obfuscate.transform(source, {
    steps = {
        "split_strings",
        "numbers_to_expressions",
        "constant_array",
        "proxify_locals",
        function(ast, context)
            context.options.custom_stage_used = true
        end
    }
})
```

### Reproducible generation

```bash
./dazeghost --obfuscate --seed 123456789 \
  --input script.lua --output protected.lua
```

The same source, decoy content, options, and seed produce the same artifact. Omitting the seed changes the actual layout and runtime material, not only the file hash.

### Generated runtime secret

```bash
./dazeghost --obfuscate --secret \
  --secret-file release.secret.txt \
  --input script.lua --output protected.lua
```

The secret file is created with owner read/write permissions where supported. Keep it separate from the artifact:

```bash
chmod 600 release.secret.txt
secret=$(cat release.secret.txt)
echo "$secret" | lua5.4 protected.lua
```

The loader asks for the secret before decrypting the payload. A wrong secret aborts execution. The generated secret is not written into the Lua file.

### Supplied runtime secret

```bash
./dazeghost --obfuscate \
  --secret='correct horse battery staple' \
  --input script.lua --output protected.lua
```

Avoid shell history, process listings, CI logs, and public command output when handling sensitive values.

### Final packing

```bash
./dazeghost --obfuscate --compress \
  --input script.lua --output protected.lua
```

Packing is attempted after all requested rounds. Because the loader has overhead, the packed form is selected only when its complete size is smaller.

### Native single-file loader

```bash
./dazeghost --obfuscate --mode text --secret \
  --secret-file release.secret.txt \
  --native-loader \
  --input script.lua \
  --output protected
```

This mode appends the protected Lua loader to the native `dazeghost-loader` template. The result is one executable file that contains the complete Lua 5.4 runtime, the protected payload, and the payload metadata. It does not require a separate `lua5.4` installation at execution time.

The generated file is executable on the platform and architecture used for the build. A native artifact must be rebuilt for another operating-system or CPU/ABI target. The runtime password prompt is provided by the protected payload:

```bash
secret=$(cat release.secret.txt)
printf '%s\n' "$secret" | ./protected
```

`--native-loader` requires a secret because the native artifact is intended to be a password-gated distribution unit. The generator fails early if the native template is unavailable or if an output path is not supplied.

The native loader registers `dazeghost_load` inside the embedded VM. Protected layers use this C++ loading boundary when it exists and fall back to Lua's `load` for regular `.lua` output. This removes the most obvious Lua-level load hook from native execution while preserving compatibility with ordinary Lua loaders.

### Separate artifact-bound VM

```bash
./dazeghost --obfuscate --mode text \
  --input script.lua \
  --output protected.lua \
  --separate-vm protected-vm
```

This mode produces two files:

- `protected.lua`: the protected Lua artifact;
- `protected-vm`: a native Lua 5.4 VM bound to that artifact.

The VM does not accept a payload path or alternate input. It resolves only the artifact with the recorded filename beside itself, verifies its SHA-256 digest, and aborts if the artifact is missing, renamed, replaced, or modified. The binding metadata is appended to the native executable and the VM is executable without a separate Lua installation.

The VM is bound to the artifact contents, not merely to its filename. Moving both files together is supported; changing either file invalidates the relationship. This is an artifact-integrity and distribution-binding mechanism, not a guarantee against a user who controls the VM process and can patch or instrument it.

The separated VM uses OpenSSL's SHA-256 implementation and therefore requires a compatible OpenSSL Crypto runtime on the target system unless the project is linked against a static deployment of that library.

`--separate-vm` and `--native-loader` are mutually exclusive. The separate mode keeps the protected artifact outside the executable, while the single-file mode embeds it inside the executable.

## Runtime password protection

The password option is a runtime access gate and key-diversification layer:

1. The generator derives per-layer material from the supplied or generated secret.
2. The secret itself is not emitted into the loader.
3. The loader asks for the secret before reconstructing the payload key.
4. The entered value is checked before payload execution.
5. A process-global cache avoids repeated prompts through nested sealing layers.

The loader requires `io.read` and standard input. For non-interactive use, provide the secret through a controlled pipe. Do not log or expose it.

When enabled, the anti-tamper option checks for an active `debug` hook through `debug.gethook`. This is intentionally best-effort and may reject debuggers or profilers; a host-controlled process can still remove or replace the check.

This is not a hardware-backed key store or a guarantee against a hostile machine owner. An analyst can patch the check, instrument the loader, inspect memory after decryption, or capture the entered secret.

## Rounds, staging, and memory

The C++ CLI registers a stage callback for obfuscation. After each round, the current output is written to a temporary stage file, read for the next round, and removed. Historical round outputs are not retained as a collection.

The parser, transformer, Lua compiler, and sealing stage still operate on the current source as a complete string. Staging limits retained historical output and provides a file boundary; it does not make the individual parser or compiler streaming.

Later rounds use larger blocks and lower sealing-noise defaults when these values are not explicitly provided. This controls growth while preserving independent randomization.

Recommended starting points:

```bash
./dazeghost --obfuscate --rounds 1 -i script.lua -o protected.lua
./dazeghost --obfuscate --rounds 3 --density 50 -i script.lua -o protected.lua
./dazeghost --obfuscate --rounds 5 --density 25 \
  --max-output-bytes 33554432 -i script.lua -o protected.lua
```

Increase output limits deliberately and monitor memory for large five-round inputs.

## Final packing format

`src.compress` uses an LZ-style stream with literal records and overlap-safe back references. Packed bytes are embedded directly as an escaped Lua binary literal. The output does not use Base64 or an external decompression library.

The generated loader decodes the literal, validates record boundaries and distances, reconstructs the original Lua chunk, checks an FNV-1a integrity value, loads the recovered chunk, and executes it.

The checksum detects corruption and basic tampering. It is not a digital signature and does not establish publisher authenticity.

## Lua library API

```lua
package.path = "./?.lua;" .. package.path

local minify = require("src.minify")
local obfuscate = require("src.obfuscate")
local compress = require("src.compress")

local source = "return 6 * 7"
local compact = minify.minify(source)
local protected = obfuscate.obfuscate(source, {
    anti_ia = true,
    decoy_src = "caos.lua",
    rounds = 3,
    decoy_density = 70,
    mode = "bytecode",
    runtime = "auto",
    seed = 1234,
    secret = "runtime secret"
})
local packed_loader = compress.wrap(protected)
```

### `src.minify`

```lua
local minify = require("src.minify")
local result = minify.minify(source)
```

This parses and re-emits compact Lua. It does not provide secrecy.

### `src.obfuscate`

```lua
local obfuscate = require("src.obfuscate")
local result = obfuscate.obfuscate(source, options)
```

Important options include `anti_ia`, `decoy_src`, `decoy_path`, `rounds`, `mix_original`, `decoy_density`, `max_decoy_fragments`, `flatten`, `rename_locals`, `encode_strings`, `split_strings`, `split_min_length`, `numbers_to_expressions`, `constant_array`, `proxify_locals`, `watermark`, `anti_tamper`, `steps`, `min_chunk_size`, `max_chunk_size`, `noise_density`, `strip`, `mode`, `runtime`, `seed`, `secret`, `max_output_bytes`, `max_intermediate_bytes`, `compress_rounds`, and `stage_writer`.

`stage_writer` receives `(data, round)` and must return the string passed into the next round. The C++ CLI supplies this callback to provide staged file boundaries.

### `src.crypt`

```lua
local crypt = require("src.crypt")
local loader = crypt.seal(source, {
    mode = "text",
    runtime = "state",
    secret = "runtime secret"
})
```

`crypt.seal` creates one protected loader layer. It validates the source before sealing. The generated loader reconstructs its payload and invokes Lua's loader for the selected mode.

### `src.compress`

```lua
local compress = require("src.compress")
local packed = compress.pack(data)
local restored = compress.unpack(packed)
local loader = compress.wrap(data)
```

`pack` and `unpack` operate on byte strings. `wrap` creates a self-contained loader with integrity validation.

## Architecture

```text
C++ CLI
  ├─ argument validation and progress reporting
  ├─ filesystem input, output, and secret handling
  ├─ per-round stage callback
  └─ embedded Lua 5.4 runtime
       ├─ lexer
       ├─ parser
       ├─ lexical binder
       ├─ decoy weaver
       ├─ source transformer
       ├─ configurable AST transformation pipeline
       │    ├─ string splitting
       │    ├─ numeric expression rewriting
       │    ├─ constant pooling
       │    ├─ local proxy indirection
       │    └─ watermark validation
       ├─ compact emitter
       ├─ sealing runtime generator
       └─ final LZ-style packer
```

The C++ executable is the supported user-facing entry point. Lua modules remain separate so transformation rules can be tested independently from the process wrapper.

## Validation

Lua syntax checks:

```bash
for file in src/*.lua tests/*.lua tests/cli/run.lua; do
  luac5.4 -p "$file"
done
```

Complete Lua suite:

```bash
lua5.4 tests/test.lua
lua5.4 tests/regression.lua
lua5.4 tests/property.lua
lua5.4 tests/rounds.lua
lua5.4 tests/text.lua
lua5.4 tests/runtime.lua
lua5.4 tests/seed.lua
lua5.4 tests/compress.lua
lua5.4 tests/password.lua
lua5.4 tests/transformations.lua
lua5.4 tests/cli/run.lua
```

C++ smoke test:

```bash
cmake -B build -S .
cmake --build build
./dazeghost --help
./dazeghost --obfuscate --mode text \
  --input script.lua --output /tmp/protected.lua
lua5.4 /tmp/protected.lua
bash tests/native_loader.sh
```

## Security model and limitations

### Self-contained loaders cannot provide perfect secrecy

If a loader can decrypt and execute a payload on a host controlled by the analyst, the analyst can eventually observe the key, plaintext, or execution state. Runtime password protection raises the cost of casual extraction but cannot create a trust boundary on an untrusted machine.

### Native execution uses the complete Lua 5.4 VM

The native loader embeds the official Lua 5.4 runtime and executes the recovered payload with that VM. This provides complete Lua 5.4 language and standard-library semantics supported by the embedded build; it is not a partial custom interpreter.

The regular Lua output mode remains a Lua loader and therefore requires a compatible Lua 5.4 interpreter at execution time. The native loader is the portable single-file option within the operating-system and architecture family for which it was compiled.

### No guaranteed anti-debugging

The current release does not provide a complete anti-debugging system. The optional hook check and the native `dazeghost_load` boundary raise the cost of simple instrumentation, but a host-controlled process can be traced, paused, instrumented, modified, or run under another Lua runtime.

### Integrity is not authenticity

The FNV-1a checksum detects corruption but is not a digital signature. It does not prove publisher authenticity and cannot prevent modification of the loader itself.

### Bytecode compatibility

`bytecode` mode depends on Lua 5.4 bytecode compatibility, including platform characteristics and build configuration. Use `text` mode when portability across Lua 5.4 installations matters more than size.

### Decoys are not executable protection

Decoy material increases structural noise but can be identified and removed through dynamic execution, control-flow analysis, or instrumentation. The decoy input is intentionally not executed during generation.

For real authorization, licensing, and sensitive business logic, keep the decision or computation on a server or inside a separately secured native component.

## Repository layout

| Path                    | Purpose                                                                                                                     |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `cpp/main.cpp`          | C++17 generator CLI, embedded Lua runtime, progress reporting, staging, secret-file handling, and native VM packaging.     |
| `cpp/native_loader.cpp` | Native Lua 5.4 VM supporting embedded payloads and artifact-bound separated execution.                                  |
| `src/lexer.lua`         | Lua 5.4 lexer.                                                                                                              |
| `src/parser.lua`        | Recursive-descent and Pratt parser.                                                                                         |
| `src/bind.lua`          | Lexical scope binding.                                                                                                      |
| `src/emit.lua`          | Compact Lua source emitter.                                                                                                 |
| `src/weave.lua`         | Conservative decoy weaving.                                                                                                 |
| `src/crypt.lua`         | Payload sealing and runtime loader generation.                                                                              |
| `src/compress.lua`      | LZ-style packing and single-file loader generation.                                                                         |
| `src/random.lua`        | 128-bit random-state initialization.                                                                                        |
| `src/minify.lua`        | Minification API.                                                                                                           |
| `src/obfuscate.lua`     | Transformation and multi-round orchestration API.                                                                           |
| `src/pipeline.lua`      | Ordered built-in and custom AST transformation stages.                                                                      |
| `src/steps/`            | String splitting, numeric expressions, constant pooling, local proxy indirection, and watermark stages.                     |
| `tests/`                | Semantic, property, runtime, seed, compression, password, native-loader, separated-VM, and integration tests.             |
| `CMakeLists.txt`        | Portable CMake build with system-Lua detection and bundled Lua fallback.                                                    |

## License

MIT
