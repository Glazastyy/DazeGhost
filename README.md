# DazeGhost

Lua 5.4 minifier and obfuscator. Pipeline: lex → parse → bind → transform → emit.

## What it does

- **minify**: parse Lua 5.4, drop comments and extra whitespace, reprint a compact equivalent program
- **obfuscate**: minify, rename locals / parameters / loop variables to `_1`, `_2`, …, rewrite string literals as decimal escapes, compile with `string.dump`, then encrypt the bytecode with a rolling key
- **`--anti-ia`**: with obfuscate, also emit unused restore helpers and notes that look like the real decoder (wrong key schedule, text mode instead of bytecode). The running program does not call them

Globals, table keys written as `name =`, and method names are left alone.

This will not stop someone who extracts the live loader and the key from the file. It is meant to make casual reading and automated reconstruction expensive.

## Requirements

- Lua 5.4 (`lua5.4`)
- For the C++ CLI: CMake 3.16+, a C++17 compiler, `liblua5.4-dev`

## Lua CLI

```bash
lua5.4 dazeghost.lua --minify file.lua
lua5.4 dazeghost.lua --obfuscate -o out.lua file.lua
lua5.4 dazeghost.lua --obfuscate --anti-ia -o out.lua file.lua
```

Default mode is `--obfuscate`.

## Library

```lua
package.path = "./?.lua;" .. package.path
local minify = require("src.minify")
local obfuscate = require("src.obfuscate")

print(minify.minify(src))
print(obfuscate.obfuscate(src))
print(obfuscate.obfuscate(src, { anti_ia = true }))
```

## C++ CLI

```bash
cmake -B build -S .
cmake --build build
./build/dazeghost --minify file.lua
./build/dazeghost --obfuscate --anti-ia -o out.lua file.lua
```

The binary looks for `src/parser.lua` next to the executable, one directory up, in `$DAZEGHOST_ROOT`, or in the current working directory.

## Tests

```bash
lua5.4 tests/test.lua
```

## Layout

- `src/lexer.lua` — Lua 5.4 scanner
- `src/parser.lua` — recursive-descent + Pratt parser
- `src/bind.lua` — lexical scope for locals
- `src/emit.lua` — compact printer
- `src/crypt.lua` — bytecode seal and optional decoy restore
- `src/minify.lua` / `src/obfuscate.lua`
- `dazeghost.lua` — Lua CLI
- `cpp/main.cpp` — C++ CLI

## License

MIT

---

# DazeGhost (português)

Minificador e ofuscador de Lua 5.4. Pipeline: lex → parse → bind → transform → emit.

## O que faz

- **minify**: parseia Lua 5.4, tira comentários e espaço extra, reimprime o programa compacto
- **obfuscate**: minifica, troca locais / parâmetros / variáveis de loop por `_1`, `_2`, …, reescreve strings como escapes decimais, compila com `string.dump` e cifra o bytecode com uma chave rolante
- **`--anti-ia`**: no obfuscate, também emite helpers e notas de restore que parecem o decoder de verdade (agenda de chave errada, modo texto em vez de bytecode). O programa que roda não chama isso

Globais, chaves de tabela no estilo `nome =` e nomes de método ficam.

Isso não para quem extrair o loader ao vivo e a chave do arquivo. Serve pra deixar leitura casual e reconstrução automática cara.

## Requisitos

- Lua 5.4 (`lua5.4`)
- Para o CLI em C++: CMake 3.16+, compilador C++17, `liblua5.4-dev`

## CLI em Lua

```bash
lua5.4 dazeghost.lua --minify arquivo.lua
lua5.4 dazeghost.lua --obfuscate -o saida.lua arquivo.lua
lua5.4 dazeghost.lua --obfuscate --anti-ia -o saida.lua arquivo.lua
```

O modo padrão é `--obfuscate`.

## Biblioteca

```lua
package.path = "./?.lua;" .. package.path
local minify = require("src.minify")
local obfuscate = require("src.obfuscate")

print(minify.minify(src))
print(obfuscate.obfuscate(src))
print(obfuscate.obfuscate(src, { anti_ia = true }))
```

## CLI em C++

```bash
cmake -B build -S .
cmake --build build
./build/dazeghost --minify arquivo.lua
./build/dazeghost --obfuscate --anti-ia -o saida.lua arquivo.lua
```

O binário procura `src/parser.lua` ao lado do executável, um diretório acima, em `$DAZEGHOST_ROOT` ou no diretório atual.

## Testes

```bash
lua5.4 tests/test.lua
```

## Layout

- `src/lexer.lua` — scanner Lua 5.4
- `src/parser.lua` — parser recursive-descent + Pratt
- `src/bind.lua` — escopo léxico dos locais
- `src/emit.lua` — impressão compacta
- `src/crypt.lua` — selo de bytecode e restore isca
- `src/minify.lua` / `src/obfuscate.lua`
- `dazeghost.lua` — CLI Lua
- `cpp/main.cpp` — CLI C++

## Licença

MIT
