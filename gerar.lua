local obfuscate = require("src.obfuscate")
local compress = require("src.compress")

local function help()
    print(table.concat({
        "Uso: lua5.4 gerar.lua --input script.lua --decoy caos.lua --output protegido.lua --rounds 3",
        "Opcoes:",
        "  --input, -i          Arquivo Lua original (padrao: script.lua)",
        "  --decoy, -d          Arquivo Lua de distracao (padrao: caos.lua)",
        "  --output, -o         Arquivo Lua gerado (padrao: protegido.lua)",
        "  --rounds, -r         Camadas de ofuscacao, de 1 a 5 (padrao: 1)",
        "  --mode               bytecode ou text (padrao: bytecode)",
        "  --compress           Comprime o arquivo final em um loader unico",
        "  --runtime            auto, linear, state ou table (padrao: auto)",
        "  --seed               Inteiro para gerar resultados reproduziveis",
        "  --density            Percentual de pontos de mistura, de 1 a 100",
        "  --min-chunk-size     Tamanho minimo dos blocos",
        "  --max-chunk-size     Tamanho maximo dos blocos",
        "  --noise-density      Percentual de instrucoes de ruido, de 0 a 100",
        "  --max-output-bytes   Limite para o arquivo gerado",
        "  --max-intermediate-bytes Limite para fontes intermediarias",
        "  --no-mix-original    Desativa a reinsercao de estruturas originais nas rodadas extras",
        "  --no-flatten         Desativa a reorganizacao de fluxo simples",
        "  --no-encode-strings  Desativa a codificacao de strings",
        "  --help, -h           Mostra esta ajuda"
    }, "\n"))
end

local defaults = {
    input = "script.lua",
    decoy = "caos.lua",
    output = "protegido.lua",
    rounds = 1,
    mode = "bytecode",
    compress = false,
    runtime = "auto",
    mix_original = true,
    flatten = true,
    encode_strings = true
}

local opts = {}
for key, value in pairs(defaults) do
    opts[key] = value
end

local parameters = {
    ["--input"] = "input", ["-i"] = "input",
    ["--decoy"] = "decoy", ["-d"] = "decoy",
    ["--output"] = "output", ["-o"] = "output",
    ["--rounds"] = "rounds", ["-r"] = "rounds",
    ["--mode"] = "mode", ["--runtime"] = "runtime", ["--seed"] = "seed",
    ["--density"] = "decoy_density",
    ["--min-chunk-size"] = "min_chunk_size",
    ["--max-chunk-size"] = "max_chunk_size",
    ["--noise-density"] = "noise_density",
    ["--max-output-bytes"] = "max_output_bytes",
    ["--max-intermediate-bytes"] = "max_intermediate_bytes"
}

local numeric = {
    rounds = true, seed = true, decoy_density = true,
    min_chunk_size = true, max_chunk_size = true, noise_density = true,
    max_output_bytes = true, max_intermediate_bytes = true
}

local argv = type(arg) == "table" and arg or {}
local cursor = 1
while cursor <= #argv do
    local flag = argv[cursor]
    if flag == "--help" or flag == "-h" then
        help()
        return
    elseif flag == "--no-mix-original" then
        opts.mix_original = false
    elseif flag == "--no-flatten" then
        opts.flatten = false
    elseif flag == "--no-encode-strings" then
        opts.encode_strings = false
    elseif flag == "--compress" then
        opts.compress = true
    else
        local key = parameters[flag]
        if not key then
            error("opcao desconhecida: " .. tostring(flag), 0)
        end
        cursor = cursor + 1
        local value = argv[cursor]
        if not value then
            error("faltando valor para " .. flag, 0)
        end
        if numeric[key] then
            value = tonumber(value)
            if not value then
                error("valor numerico invalido para " .. flag, 0)
            end
        end
        opts[key] = value
    end
    cursor = cursor + 1
end

local function readFile(path)
    local file, err = io.open(path, "rb")
    if not file then
        error("nao foi possivel abrir " .. path .. ": " .. tostring(err), 0)
    end
    local content = assert(file:read("*a"))
    file:close()
    return content
end

local source = readFile(opts.input)
local function writeStage(data, round)
    local path = opts.output .. ".stage." .. tostring(round)
    local stage = assert(io.open(path, "wb"))
    assert(stage:write(data))
    stage:close()
    local content = readFile(path)
    assert(os.remove(path))
    collectgarbage("collect")
    return content
end
local output = obfuscate.obfuscate(source, {
    anti_ia = true,
    decoy_src = opts.decoy,
    rounds = opts.rounds,
    mix_original = opts.mix_original,
    mode = opts.mode,
    runtime = opts.runtime,
    seed = opts.seed,
    decoy_density = opts.decoy_density,
    min_chunk_size = opts.min_chunk_size,
    max_chunk_size = opts.max_chunk_size,
    noise_density = opts.noise_density,
    max_output_bytes = opts.max_output_bytes,
    max_intermediate_bytes = opts.max_intermediate_bytes,
    flatten = opts.flatten,
    encode_strings = opts.encode_strings,
    rename_locals = true,
    strip = true,
    stage_writer = writeStage
})

if opts.compress then
    local compressed = compress.wrap(output)
    if #compressed < #output then
        output = compressed
    end
end

local file, err = io.open(opts.output, "wb")
if not file then
    error("nao foi possivel gravar " .. opts.output .. ": " .. tostring(err), 0)
end
assert(file:write(output))
file:close()

print("Arquivo gerado: " .. opts.output)
print("Rodadas: " .. opts.rounds)
print("Tamanho: " .. #output .. " bytes")
