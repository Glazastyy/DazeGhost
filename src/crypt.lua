local M = {}

local function keys(s)
    local a, b = 1, 3
    for i = 1, #s do
        local x = s:byte(i)
        a = (a * 131 + x * i) % 251 + 1
        b = (b * 137 + x + i) % 241 + 1
    end
    return a, b
end

local function mixbyte(p, i, a, b)
    local k = ((a * i + b) ~ (i * 2)) & 255
    return (p ~ k) & 255
end

local function mix(s, a, b)
    local t = {}
    for i = 1, #s do
        t[i] = string.char(mixbyte(s:byte(i), i, a, b))
    end
    return table.concat(t)
end

local function packnums(s)
    local parts = {}
    local buf = {}
    for i = 1, #s do
        buf[#buf + 1] = tostring(s:byte(i))
        if #buf == 32 then
            parts[#parts + 1] = table.concat(buf, ",")
            buf = {}
        end
    end
    if #buf > 0 then
        parts[#parts + 1] = table.concat(buf, ",")
    end
    if #parts == 0 then
        return "{}"
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local DECOY = [=[
--[[
  restore notes (Lua 5.4)
  v is a text chunk (not bytecode). stream: s[i] = v[i] ~ ((a + i) % 256)
  b is a checksum only; ignore it when rebuilding source.
  load the result with mode "t" so lineinfo survives.
]]
local function restore_v1(v, a, b)
    local s = {}
    for i = 1, #v do
        s[i] = string.char((v[i] ~ ((a + i) % 256)) & 255)
    end
    return load(table.concat(s), "=restore", "t")
end
-- older dumps: skip the 12-byte header, then xor 0x5A
local function restore_legacy(v)
    local s = {}
    for i = 1, #v do
        s[i] = string.char((v[i] ~ 90) & 255)
    end
    local raw = table.concat(s)
    if #raw > 12 then
        raw = raw:sub(13)
    end
    return load(raw, nil, "t")
end
]=]

function M.seal(src, opts)
    opts = opts or {}
    local fn, err = load(src, "=dazeghost", "t")
    if not fn then
        error("cannot compile for seal: " .. tostring(err))
    end
    local dump = string.dump(fn, true)
    local a, b = keys(dump)
    local enc = mix(dump, a, b)
    local payload = packnums(enc)
    local prefix = ""
    if opts.anti_ia then
        prefix = DECOY
    end
    return table.concat({
        prefix,
        "return(function(v,a,b)\n",
        "local s={}\n",
        "local n=#v\n",
        "local i=1\n",
        "while i<=n do\n",
        "local k=((a*i+b)~(i*2))&255\n",
        "s[i]=string.char((v[i]~k)&255)\n",
        "i=i+1\n",
        "end\n",
        "return assert(load(table.concat(s),nil,\"b\"))()\n",
        "end)(",
        payload,
        ",",
        tostring(a),
        ",",
        tostring(b),
        ")",
    })
end

return M
