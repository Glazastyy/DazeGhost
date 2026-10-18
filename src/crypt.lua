local M = {}

local MASK = 0xFFFFFFFF

local function hash(data)
    local value = 2166136261
    for i = 1, #data do
        value = ((value ~ data:byte(i)) * 16777619) & MASK
    end
    return value
end

local function entropy()
    local file = io.open("/dev/urandom", "rb")
    if file then
        local data = file:read(4)
        file:close()
        if data and #data == 4 then
            return string.unpack("<I4", data)
        end
    end
    return (os.time() ~ math.floor(os.clock() * 1000000) ~ math.random(0, 0x7FFFFFFF)) & MASK
end

local function rng(initial)
    local state = initial & MASK
    if state == 0 then
        state = 0x9E3779B9
    end
    return function(minimum, maximum)
        state = (state ~ ((state << 13) & MASK)) & MASK
        state = (state ~ (state >> 17)) & MASK
        state = (state ~ ((state << 5) & MASK)) & MASK
        if minimum ~= nil then
            return minimum + state % (maximum - minimum + 1)
        end
        return state
    end
end

local function validate(opts)
    if type(opts) ~= "table" then
        error("options must be a table", 3)
    end
    local minimum = opts.min_chunk_size or 24
    local maximum = opts.max_chunk_size or 80
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
    return minimum, maximum
end

local function encrypt(data, key, multiplier, increment)
    local state = key
    local result = {}
    for i = 1, #data do
        state = (state * multiplier + increment) & MASK
        local byte = (data:byte(i) ~ ((state >> 16) & 255) ~ ((state >> 7) & 255) ~ (i & 255)) & 255
        result[i] = string.char(byte)
        state = (state ~ (byte * 257 + i)) & MASK
    end
    return table.concat(result)
end

local function shuffle(items, random)
    for i = #items, 2, -1 do
        local j = random(1, i)
        items[i], items[j] = items[j], items[i]
    end
end

local function packBytes(data)
    local result = {}
    for i = 1, #data do
        result[i] = tostring(data:byte(i))
    end
    return "{" .. table.concat(result, ",") .. "}"
end

local function assemble(data, minimum, maximum, random)
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
        if random(0, 3) == 0 then
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

local function makeLoader(blocks, instructions, entry, opChunk, opNoise, opEnd, key, multiplier, increment, checksum, mode, variant)
    local args = table.concat({
        blocks, instructions, tostring(entry), tostring(opChunk), tostring(opNoise), tostring(opEnd),
        tostring(key), tostring(multiplier), tostring(increment), tostring(checksum),
        mode == "text" and "'t'" or "'b'"
    }, ",")
    local prefix = "return(function(P,I,H,A,B,Z,K,M,N,E,Q)"
    local suffix = "if h~=E then error('payload integrity check failed') end;local fn,err=load(CONCAT(O),nil,Q);if not fn then error(err) end;return fn() end)(" .. args .. ")"
    if variant == "linear" then
        return table.concat({
            prefix,
            "local CH,CONCAT=string.char,table.concat;local O={};local h=2166136261;local s=K;local pos=0;local pc=H;",
            "while pc~=0 do local ins=I[pc];if not ins then error('invalid instruction') end;",
            "local op,index=ins[1],ins[2];",
            "if op==Z then break elseif op==A then local data=P[index];if not data then error('missing block') end;",
            "for j=1,#data do pos=pos+1;s=(s*M+N)&0xFFFFFFFF;local c=data[j];",
            "local x=(c~((s>>16)&255)~((s>>7)&255)~(pos&255))&255;",
            "O[pos]=CH(x);h=((h~x)*16777619)&0xFFFFFFFF;",
            "s=(s~(c*257+pos))&0xFFFFFFFF;end;",
            "elseif op~=B then error('invalid opcode') end;pc=ins[3];end;",
            suffix
        })
    end
    if variant == "state" then
        return table.concat({
            prefix,
            "local CH,CONCAT=string.char,table.concat;local O={};local h=2166136261;local s=K;local pos=0;local pc=H;local done=false;",
            "while not done do local ins=I[pc];if not ins then error('invalid instruction') end;local op,index=ins[1],ins[2];",
            "if op==Z then done=true elseif op==A then local data=P[index];if not data then error('missing block') end;",
            "for j,c in ipairs(data) do pos=pos+1;s=(s*M+N)&0xFFFFFFFF;local x=(c~((s>>16)&255)~((s>>7)&255)~(pos&255))&0xFF;O[pos]=CH(x);h=((h~x)*16777619)&0xFFFFFFFF;s=(s~(c*257+pos))&0xFFFFFFFF;end;pc=ins[3];",
            "elseif op==B then pc=ins[3];else error('invalid opcode') end;end;",
            suffix
        })
    end
    return table.concat({
        prefix,
        "local CH,CONCAT=string.char,table.concat;local O={};local h=2166136261;local s=K;local pos=0;local pc=H;",
        "local function chunk(index)local data=P[index];if not data then error('missing block') end;for j=1,#data do pos=pos+1;s=(s*M+N)&0xFFFFFFFF;local c=data[j];local x=(c~((s>>16)&255)~((s>>7)&255)~(pos&255))&255;O[pos]=CH(x);h=((h~x)*16777619)&0xFFFFFFFF;s=(s~(c*257+pos))&0xFFFFFFFF end end;",
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
    local minimum, maximum = validate(opts)
    if opts.anti_ia == true and opts._decoy_woven ~= true then
        source = require("src.weave").weave(source, opts)
    end
    local chunk, err = load(source, "=dazeghost", "t")
    if not chunk then
        error("cannot compile source: " .. tostring(err), 2)
    end
    local mode = opts.mode or "bytecode"
    local raw = mode == "text" and source or string.dump(chunk, opts.strip ~= false)
    local random = rng((opts.seed or entropy()) ~ hash(raw))
    local key = random()
    local multiplier = (random() | 1) & MASK
    local increment = (random() | 1) & MASK
    local encrypted = encrypt(raw, key, multiplier, increment)
    local blocks, instructions, entry, opChunk, opNoise, opEnd = assemble(encrypted, minimum, maximum, random)
    local runtime = opts.runtime or "auto"
    if runtime == "auto" then
        runtime = ({ "linear", "state", "table" })[random(1, 3)]
    end
    return makeLoader(blocks, instructions, entry, opChunk, opNoise, opEnd, key, multiplier, increment, hash(raw), mode, runtime)
end

return M
