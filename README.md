# DazeGhost

Lua 5.4 minifier and obfuscator. Pipeline: lex → parse → bind → transform → emit.

## What it does

- **minify**: parse Lua 5.4, drop comments and extra whitespace, reprint a compact equivalent program
- **obfuscate**: transform the source, compile it when requested, protect the payload with a keyed ARX stream mixer and integrity check, and select a diversified runtime dispatcher per build
- **`--anti-ia`**: with obfuscate, also emit unused restore helpers and notes that look like the real decoder (wrong key schedule, text mode instead of bytecode). The running program does not call them

Globals, table keys written as `name =`, and method names are left alone.

The loader distributes the key material as split shares and reconstructs it only inside the runtime, but this is obfuscation rather than secret storage. A self-contained loader cannot hide a secret from an analyst who can execute it. Sensitive decisions should remain server-side.

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
./build/dazeghost --obfuscate --anti-ia --rounds 3 --density 70 --runtime auto -o out.lua file.lua
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
- **obfuscate**: transforma o código, compila quando solicitado, protege o payload com uma mistura ARX dependente de chave e verificação de integridade, e escolhe um dispatcher de runtime diversificado por build
- **`--anti-ia`**: no obfuscate, também emite helpers e notas de restore que parecem o decoder de verdade (agenda de chave errada, modo texto em vez de bytecode). O programa que roda não chama isso

Globais, chaves de tabela no estilo `nome =` e nomes de método ficam.

O loader distribui o material da chave em shares e só o recompõe durante a execução, mas isso é ofuscação, não armazenamento secreto. Um loader autocontido não consegue esconder um segredo de quem pode executá-lo. Decisões sensíveis devem permanecer no servidor.

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
./build/dazeghost --obfuscate --anti-ia --rounds 3 --density 70 --runtime auto -o saida.lua arquivo.lua
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


# DazeGhost: ofuscação Lua 5.4

Este pacote fornece os oito módulos de `src/`, um gerador `gerar.lua` e testes. Os arquivos `dazeghost.lua`, `cpp/main.cpp` e `CMakeLists.txt` do projeto original não foram fornecidos e não foram alterados.

## Requisitos

É necessário Lua 5.4 para geração e execução. No modo `bytecode`, as instalações que geram e executam o arquivo precisam usar formatos de bytecode Lua compatíveis.

## Uso mais simples

Na raiz do DazeGhost, com `script.lua`, `caos.lua`, `src/` e `gerar.lua`:

```bash
lua5.4 gerar.lua --input script.lua --decoy caos.lua --output protegido.lua --rounds 3
```

Para ajustar a densidade dos fragmentos de distração:

```bash
lua5.4 gerar.lua -i script.lua -d caos.lua -o protegido.lua -r 2 --density 70
```

Para mostrar todas as opções:

```bash
lua5.4 gerar.lua --help
```

Para gerar um loader único com o payload final compactado quando a compactação realmente reduzir o arquivo:

```bash
lua5.4 gerar.lua --input script.lua --decoy caos.lua --output protegido.lua --rounds 3 --density 70 --compress
```

## Uso programático

O campo `decoy_src` aceita o caminho de um arquivo Lua existente ou código Lua diretamente como string. `decoy_path` é uma opção alternativa que aceita apenas caminho. Caso um valor com aparência de arquivo `.lua` não exista, será apresentado um erro, em vez de tentar interpretar o nome do arquivo como código.

```lua
local obfuscate = require("src.obfuscate")

local file = assert(io.open("script.lua", "rb"))
local source = assert(file:read("*a"))
file:close()

local result = obfuscate.obfuscate(source, {
    anti_ia = true,
    decoy_src = "caos.lua",
    rounds = 3,
    mix_original = true,
    decoy_density = 70,
    max_decoy_fragments = 96,
    flatten = true,
    rename_locals = true,
    encode_strings = true,
    min_chunk_size = 24,
    max_chunk_size = 80,
    noise_density = 25,
    strip = true,
    mode = "bytecode",
    runtime = "auto"
})

local output = assert(io.open("protegido.lua", "wb"))
assert(output:write(result))
output:close()
```

## Como funcionam as rodadas

A rodada 1 intercala declarações de distração na estrutura sintática do programa real, aplica as transformações e sela o resultado. Cada rodada posterior trabalha a partir do arquivo já selado pela rodada anterior. Se `mix_original` estiver ativo, fragmentos do código original também entram no conjunto de distrações das rodadas seguintes, junto ao conteúdo de `caos.lua`. Assim, as estruturas são combinadas antes da compilação, e não guardadas em um segundo payload independente.

A inserção é conservadora: não executa o programa `caos.lua`, pois não seria seguro presumir que um programa arbitrário de distração é livre de efeitos colaterais. Em certos pontos, o trecho verdadeiro é colocado em um ramo condicional cujo resultado é previsível durante a geração, e o trecho falso fica em um caminho alternativo. Isso torna a saída mais complexa, mas não garante resistência à análise estática ou dinâmica.

A opção `rounds` aceita inteiros de 1 até 5. Rodadas adicionais elevam consideravelmente o tamanho final e os custos de geração e de carregamento. A opção `max_output_bytes` limita o tamanho gerado, por padrão a 12 MiB, e interrompe a operação com erro se o limite for excedido.

Cada rodada é persistida temporariamente pelo CLI em um arquivo de estágio e o estágio anterior é liberado antes da próxima rodada. A transformação individual ainda precisa manter a etapa atual em memória, porque o parser, o compilador Lua e o selador operam sobre strings completas.

## Opções principais

| Opção | Padrão | Finalidade |
| --- | --- | --- |
| `anti_ia` | `false` | Ativa mistura estrutural com fragmentos de distração |
| `decoy_src` | interno | Código Lua ou caminho para arquivo Lua de distração |
| `decoy_path` | nenhum | Caminho explícito da distração, prioritário sobre `decoy_src` |
| `rounds` | `1` | Quantidade de rodadas completas, até 5 |
| `mix_original` | `true` | Inclui fragmentos originais como distração a partir da rodada 2 |
| `decoy_density` | `100` | Probabilidade percentual de inserir distrações nos pontos elegíveis |
| `max_decoy_fragments` | `192` | Quantidade máxima de fragmentos de distração coletados |
| `flatten` | `true` | Transforma conjuntos seguros de chamadas e atribuições em fluxo por estados |
| `rename_locals` | `true` | Renomeia locais, respeitando escopo e `_ENV` |
| `encode_strings` | `true` | Ofusca literais de strings com decodificação sob demanda |
| `min_chunk_size` | `24` | Tamanho mínimo de cada fragmento de dados |
| `max_chunk_size` | `80` | Tamanho máximo, limitado a 4096 |
| `noise_density` | `25` | Percentual de instruções de ruído inseridas pelo selador; nas rodadas posteriores, o padrão interno é reduzido para controlar crescimento |
| `strip` | `true` | Remove informações de depuração do bytecode |
| `mode` | `bytecode` | Usa payload `bytecode` ou `text` |
| `runtime` | `auto` | Escolhe o dispatcher `linear`, `state` ou `table`; `auto` diversifica por build |
| `seed` | aleatória | Semente para builds reproduzíveis |
| `seed` ausente | 128 bits de entropia do sistema | Gera uma saída nova a cada execução; use `seed` explícita apenas para reprodução controlada |
| `max_output_bytes` | 12582912 | Limite de tamanho do arquivo resultante |
| `max_intermediate_bytes` | `max(8 × max_output_bytes, 64 MiB)` | Limite independente para fontes intermediárias entre rodadas |
| `compress_rounds` | `false` | Compacta uma camada entre rodadas somente quando o resultado fica menor |

## Interfaces

`require("src.obfuscate").obfuscate(source, options)` realiza todas as rodadas configuradas. `require("src.obfuscate").transform(source, options)` transforma uma etapa, sem empacotar. `require("src.crypt").seal(source, options)` sela um código Lua em uma camada; quando `anti_ia = true`, também aplica a mistura estrutural, se ainda não tiver sido feita pelo chamador.

`require("src.compress").wrap(source)` produz um loader Lua autocontido que decodifica, descompacta, valida a integridade e executa o conteúdo. O CLI só substitui a saída pela versão compactada quando ela é menor, evitando aumentar o arquivo por causa da codificação do loader.

## Testes

```bash
lua5.4 tests/regression.lua
lua5.4 tests/property.lua
lua5.4 tests/rounds.lua
lua5.4 tests/text.lua
lua5.4 tests/cli/run.lua
```

## Limitações

Não há virtualização completa do conjunto de instruções do Lua. O runtime possui três formas polimórficas de dispatcher, mas ainda reconstrói o payload e o passa para `load`. Os fragmentos de distração não constituem uma defesa comprovada contra IA, e caminhos inativos podem ser detectados por instrumentação e análise simbólica. O hash de integridade não é criptograficamente autenticado, a codificação dos bytes é reversível e não há antidepuração robusta. A proteção deve ser avaliada com benchmarks de engenharia reversa no ambiente de execução real.
