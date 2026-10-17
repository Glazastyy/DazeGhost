# DazeGhost

Lua 5.4 minifier and obfuscator. Pipeline: lex → parse → bind → transform → emit.

The analysis pipeline is Lua. The optional CLI is a C++17 host that loads that pipeline through the Lua 5.4 C API.

## What it does

- **minify**: parse Lua 5.4, drop comments and extra whitespace, reprint a compact equivalent program
- **obfuscate**: minify, then rename locals / parameters / loop variables to `_1`, `_2`, … and rewrite string literals as decimal escapes

Globals, table keys written as `name =`, and method names are left alone.

## Requirements

- Lua 5.4 (`lua5.4`)
- For the C++ CLI: CMake 3.16+, a C++17 compiler, `liblua5.4-dev`

## Lua CLI

```bash
lua5.4 dazeghost.lua --minify file.lua
lua5.4 dazeghost.lua --obfuscate -o out.lua file.lua
```

Default mode is `--obfuscate`.

## Library

```lua
package.path = "./?.lua;" .. package.path
local minify = require("src.minify")
local obfuscate = require("src.obfuscate")

print(minify.minify(src))
print(obfuscate.obfuscate(src))
```

## C++ CLI

```bash
cmake -B build -S .
cmake --build build
./build/dazeghost --minify file.lua
./build/dazeghost --obfuscate -o out.lua file.lua
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
- `src/minify.lua` / `src/obfuscate.lua`
- `dazeghost.lua` — Lua CLI
- `cpp/main.cpp` — C++ CLI host

This is not a bytecode VM and it will not hide a program from someone who can run `luac -l`. It is for size and for making source harder to read.

## License

MIT

---

# DazeGhost (português)

Minificador e ofuscador de Lua 5.4. Pipeline: lex → parse → bind → transform → emit.

A análise é em Lua. O CLI opcional é um host C++17 que carrega esse pipeline pela API C do Lua 5.4.

## O que faz

- **minify**: parseia Lua 5.4, tira comentários e espaço extra, reimprime o programa compacto
- **obfuscate**: minifica, troca locais / parâmetros / variáveis de loop por `_1`, `_2`, … e reescreve strings como escapes decimais

Globais, chaves de tabela no estilo `nome =` e nomes de método ficam.

## Requisitos

- Lua 5.4 (`lua5.4`)
- Para o CLI em C++: CMake 3.16+, compilador C++17, `liblua5.4-dev`

## CLI em Lua

```bash
lua5.4 dazeghost.lua --minify arquivo.lua
lua5.4 dazeghost.lua --obfuscate -o saida.lua arquivo.lua
```

O modo padrão é `--obfuscate`.

## Biblioteca

```lua
package.path = "./?.lua;" .. package.path
local minify = require("src.minify")
local obfuscate = require("src.obfuscate")

print(minify.minify(src))
print(obfuscate.obfuscate(src))
```

## CLI em C++

```bash
cmake -B build -S .
cmake --build build
./build/dazeghost --minify arquivo.lua
./build/dazeghost --obfuscate -o saida.lua arquivo.lua
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
- `src/minify.lua` / `src/obfuscate.lua`
- `dazeghost.lua` — CLI Lua
- `cpp/main.cpp` — host C++ do CLI

Não é uma VM de bytecode e não esconde o programa de quem roda `luac -l`. Serve para tamanho e para deixar o fonte mais difícil de ler.

## Licença

MIT
