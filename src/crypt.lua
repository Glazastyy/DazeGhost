local M = {}
local random128 = require("src.random")
local digest = require("src.digest")
local digestRuntime = require("src.digest_runtime")

local MASK = 0xFFFFFFFF

local function hash(data)
    return string.unpack(">I4", digest.raw(data))
end

local function passwordMaterial(password, seed)
    return string.unpack(">I4", digest.raw(string.pack("<I4", seed) .. password))
end

local function validate(opts)
    if type(opts) ~= "table" then
        error("options must be a table", 3)
    end
    local minimum = opts.min_chunk_size or 24
    local maximum = opts.max_chunk_size or 80
    local noiseDensity = opts.noise_density
    if noiseDensity == nil then
        noiseDensity = 25
    end
    if type(minimum) ~= "number" or type(maximum) ~= "number"
        or minimum % 1 ~= 0 or maximum % 1 ~= 0
        or minimum < 1 or maximum < minimum or maximum > 4096 then
        error("invalid chunk sizes", 3)
    end
    if opts.seed ~= nil and (type(opts.seed) ~= "number" or opts.seed % 1 ~= 0 or opts.seed < 0 or opts.seed > MASK) then
        error("seed must be an integer between 0 and 4294967295", 3)
    end
    if opts.mode ~= nil and opts.mode ~= "bytecode" and opts.mode ~= "text" then
        error("mode must be 'bytecode' or 'text'", 3)
    end
    if opts.runtime ~= nil and opts.runtime ~= "auto" and opts.runtime ~= "linear"
        and opts.runtime ~= "state" and opts.runtime ~= "table" then
        error("runtime must be 'auto', 'linear', 'state' or 'table'", 3)
    end
    if type(noiseDensity) ~= "number" or noiseDensity % 1 ~= 0 or noiseDensity < 0 or noiseDensity > 100 then
        error("noise_density must be an integer between 0 and 100", 3)
    end
    return minimum, maximum, noiseDensity
end

local function rotate(value, amount)
    return ((value << amount) | (value >> (32 - amount))) & MASK
end

local function encrypt(data, key, multiplier, increment)
    local a = key
    local b = multiplier
    local c = increment
    local d = (key ~ multiplier ~ increment) & MASK
    local result = {}
    local chunk = {}
    local chunkSize = 0
    local function flush()
        if chunkSize > 0 then
            result[#result + 1] = table.concat(chunk)
            chunk = {}
            chunkSize = 0
        end
    end
    for i = 1, #data do
        local input = data:byte(i)
        a = (a + b + i) & MASK
        b = rotate((b ~ a) & MASK, 7)
        c = (c + d + a) & MASK
        d = rotate((d ~ c) & MASK, 11)
        a = (a + d + increment) & MASK
        c = rotate((c ~ b) & MASK, 17)
        b = (b + c + multiplier) & MASK
        d = rotate((d ~ a) & MASK, 19)
        local output = (input ~ ((a ~ b ~ c ~ d) & 255)) & 255
        chunkSize = chunkSize + 1
        chunk[chunkSize] = string.char(output)
        if chunkSize == 4096 then
            flush()
        end
        a = (a ~ (output * 257 + i)) & MASK
        d = (d + output + i) & MASK
    end
    flush()
    return table.concat(result)
end

local function shuffle(items, random)
    for i = #items, 2, -1 do
        local j = random(1, i)
        items[i], items[j] = items[j], items[i]
    end
end

local function packBytes(data)
    return string.format("%q", data)
end

local function splitMaterial(value, salt)
    local first = ((value ~ salt) * 1664525 + 1013904223) & MASK
    return first, (value ~ first) & MASK
end

local function assemble(data, minimum, maximum, noiseDensity, random)
    local blocks = {}
    local ordered = {}
    local cursor = 1
    while cursor <= #data do
        local size = random(minimum, maximum)
        local part = { content = data:sub(cursor, cursor + size - 1) }
        blocks[#blocks + 1] = part
        ordered[#ordered + 1] = part
        cursor = cursor + size
    end
    shuffle(blocks, random)
    local physical = {}
    local packed = {}
    for i, block in ipairs(blocks) do
        physical[block] = i
        packed[i] = packBytes(block.content)
        block.content = nil
    end
    local opChunk = random(32, 240)
    local opNoise = random(32, 240)
    while opNoise == opChunk do
        opNoise = random(32, 240)
    end
    local opEnd = random(32, 240)
    while opEnd == opChunk or opEnd == opNoise do
        opEnd = random(32, 240)
    end
    local logical = {}
    for _, block in ipairs(ordered) do
        logical[#logical + 1] = { opChunk, physical[block] }
        if random(1, 100) <= noiseDensity then
            logical[#logical + 1] = { opNoise, random(1, 65535) }
        end
    end
    logical[#logical + 1] = { opEnd, 0 }
    local pointers = {}
    for i = 1, #logical do
        pointers[i] = i
    end
    shuffle(pointers, random)
    local indices = {}
    for physicalIndex, logicalIndex in ipairs(pointers) do
        indices[logicalIndex] = physicalIndex
    end
    local instructions = {}
    for i, logicalIndex in ipairs(pointers) do
        local instruction = logical[logicalIndex]
        local nextIndex = logicalIndex == #logical and 0 or indices[logicalIndex + 1]
        instructions[i] = "{" .. instruction[1] .. "," .. instruction[2] .. "," .. nextIndex .. "}"
    end
    return "{" .. table.concat(packed, ",") .. "}",
        "{" .. table.concat(instructions, ",") .. "}",
        indices[1], opChunk, opNoise, opEnd
end

local function makeLoader(blocks, instructions, entry, opChunk, opNoise, opEnd, key, multiplier, increment, checksum, mode, variant, secretVerifier, secretEnabled, random)
    local keyFirst, keySecond = splitMaterial(key, 0xA341316C)
    local multiplierFirst, multiplierSecond = splitMaterial(multiplier, 0xC8013EA4)
    local incrementFirst, incrementSecond = splitMaterial(increment, 0xAD90777D)
    local args = table.concat({
        blocks, instructions, tostring(entry), tostring(opChunk), tostring(opNoise), tostring(opEnd),
        tostring(keyFirst), tostring(keySecond), tostring(multiplierFirst), tostring(multiplierSecond),
        tostring(incrementFirst), tostring(incrementSecond), string.format("%q", checksum),
        mode == "text" and "'t'" or "'b'", string.format("%q", secretVerifier), secretEnabled and "true" or "false"
    }, ",")
    local runtimeDigest, digestNames = digestRuntime.source(random)
    local prefix = "return(function(P,I,H,A,B,Z,X1,X2,X3,X4,X5,X6,E,Q,V,W)" .. runtimeDigest .. "local q1=(X1~X2)&0xFFFFFFFF;local q2=(X3~X4)&0xFFFFFFFF;local q3=(X5~X6)&0xFFFFFFFF;local CH,CONCAT=string.char,table.concat;local O={};local a=q1;local b=q2;local c=q3;local d=(q1~q2~q3)&0xFFFFFFFF;local pos=0;local function step(input)pos=pos+1;a=(a+b+pos)&0xFFFFFFFF;b=(((b~a)<<7)|((b~a)>>25))&0xFFFFFFFF;c=(c+d+a)&0xFFFFFFFF;d=(((d~c)<<11)|((d~c)>>21))&0xFFFFFFFF;a=(a+d+q3)&0xFFFFFFFF;c=(((c~b)<<17)|((c~b)>>15))&0xFFFFFFFF;b=(b+c+q2)&0xFFFFFFFF;d=(((d~a)<<19)|((d~a)>>13))&0xFFFFFFFF;local output=(input~((a~b~c~d)&0xFF))&0xFF;O[pos]=CH(output);a=(a~(input*257+pos))&0xFFFFFFFF;d=(d+input+pos)&0xFFFFFFFF end;"
    local passwordCode = "if W then local G=rawget(_ENV,'_G') or _ENV;local password=rawget(G,'__DazeGhostPassword');if password==nil then if not io or type(io.read)~='function' then error('password input is unavailable') end;io.write('DazeGhost password: ');password=io.read('*l');if type(password)~='string' then error('password is required') end end;if " .. digestNames.dgHex .. "(" .. digestNames.dgRaw .. "(password))~=V then error('invalid password') end;rawset(G,'__DazeGhostPassword',password);local function derive(seed)return string.unpack('>I4'," .. digestNames.dgRaw .. "(string.pack('<I4',seed)..password)) end;X1=(X1~derive(0x6D2B79F5))&0xFFFFFFFF;X3=(X3~derive(0x1B873593))&0xFFFFFFFF;X5=(X5~derive(0x85EBCA6B))&0xFFFFFFFF;q1=(X1~X2)&0xFFFFFFFF;q2=(X3~X4)&0xFFFFFFFF;q3=(X5~X6)&0xFFFFFFFF;a=q1;b=q2;c=q3;d=(q1~q2~q3)&0xFFFFFFFF end;"
    prefix = prefix .. passwordCode
    local suffix = "local integrity= W and " .. digestNames.dgHmac .. "(rawget(_ENV,'__DazeGhostPassword'),CONCAT(O)) or " .. digestNames.dgHex .. "(" .. digestNames.dgRaw .. "(CONCAT(O)));if integrity~=E then error('payload integrity check failed') end;local loader=rawget(_ENV,'dazeghost_load') or load;local fn,err=loader(CONCAT(O),nil,Q);if not fn then error(err) end;return fn() end)(" .. args .. ")"
    if variant == "linear" then
        return table.concat({
            prefix,
            "local pc=H;",
            "while pc~=0 do local ins=I[pc];if not ins then error('invalid instruction') end;",
            "local op,index=ins[1],ins[2];",
            "if op==Z then break elseif op==A then local data=P[index];if not data then error('missing block') end;",
            "for j=1,#data do step(data:byte(j)) end;",
            "elseif op~=B then error('invalid opcode') end;pc=ins[3];end;",
            suffix
        })
    end
    if variant == "state" then
        return table.concat({
            prefix,
            "local pc=H;local done=false;",
            "while not done do local ins=I[pc];if not ins then error('invalid instruction') end;local op,index=ins[1],ins[2];",
            "if op==Z then done=true elseif op==A then local data=P[index];if not data then error('missing block') end;",
            "for j=1,#data do step(data:byte(j)) end;pc=ins[3];",
            "elseif op==B then pc=ins[3];else error('invalid opcode') end;end;",
            suffix
        })
    end
    return table.concat({
        prefix,
        "local pc=H;",
        "local function chunk(index)local data=P[index];if not data then error('missing block') end;for j=1,#data do step(data:byte(j)) end end;",
        "local handlers={[A]=function(index)chunk(index)end,[B]=function()end,[Z]=function()end};",
        "while true do local ins=I[pc];if not ins then error('invalid instruction') end;local handler=handlers[ins[1]];if not handler then error('invalid opcode') end;handler(ins[2]);if ins[1]==Z then break end;pc=ins[3] end;",
        suffix
    })
end

function M.seal(source, opts)
    opts = opts or {}
    if type(source) ~= "string" then
        error("source must be a string", 2)
    end
    local minimum, maximum, noiseDensity = validate(opts)
    if opts.anti_ia == true and opts._decoy_woven ~= true then
        source = require("src.weave").weave(source, opts)
    end
    local chunk, err = load(source, "=dazeghost", "t")
    if not chunk then
        error("cannot compile source: " .. tostring(err), 2)
    end
    local mode = opts.mode or "bytecode"
    local raw = mode == "text" and source or string.dump(chunk, opts.strip ~= false)
    local randomSeed
    if opts.seed ~= nil then
        randomSeed = (opts.seed ~ hash(raw)) & MASK
    end
    local random = random128.new(randomSeed)
    local key = random()
    local multiplier = (random() | 1) & MASK
    local increment = (random() | 1) & MASK
    local encrypted = encrypt(raw, key, multiplier, increment)
    local blocks, instructions, entry, opChunk, opNoise, opEnd = assemble(encrypted, minimum, maximum, noiseDensity, random)
    local runtime = opts.runtime or "auto"
    if runtime == "auto" then
        runtime = ({ "linear", "state", "table" })[random(1, 3)]
    end
    local secretVerifier = ""
    local secretEnabled = opts.secret ~= nil
    if secretEnabled then
        if type(opts.secret) ~= "string" or opts.secret == "" then
            error("secret must be a nonempty string", 2)
        end
        secretVerifier = digest.hex(opts.secret)
        key = (key ~ passwordMaterial(opts.secret, 0x6D2B79F5)) & MASK
        multiplier = (multiplier ~ passwordMaterial(opts.secret, 0x1B873593)) & MASK
        increment = (increment ~ passwordMaterial(opts.secret, 0x85EBCA6B)) & MASK
    end
    local checksum = secretEnabled and digest.hmac(opts.secret, raw) or digest.hex(raw)
    return makeLoader(blocks, instructions, entry, opChunk, opNoise, opEnd, key, multiplier, increment, checksum, mode, runtime, secretVerifier, secretEnabled, random)
end

return M
