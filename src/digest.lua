local M = {}

local MASK = 0xFFFFFFFF
local K = {
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
}

local function rotate(value, amount)
    return ((value >> amount) | ((value << (32 - amount)) & MASK)) & MASK
end

local function pad(data)
    local bitLength = #data * 8
    local padding = 56 - ((#data + 1) % 64)
    if padding < 0 then
        padding = padding + 64
    end
    local high = math.floor(bitLength / 0x100000000)
    local low = bitLength & MASK
    return data .. string.char(0x80) .. string.rep("\0", padding) .. string.pack(">I4I4", high, low)
end

function M.raw(data)
    if type(data) ~= "string" then
        error("digest input must be a string", 2)
    end
    local h0, h1, h2, h3 = 0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A
    local h4, h5, h6, h7 = 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
    local padded = pad(data)
    local words = {}
    for offset = 1, #padded, 64 do
        for index = 1, 16 do
            words[index] = string.unpack(">I4", padded, offset + (index - 1) * 4)
        end
        for index = 17, 64 do
            local value = words[index - 15]
            local first = rotate(value, 7) ~ rotate(value, 18) ~ (value >> 3)
            value = words[index - 2]
            local second = rotate(value, 17) ~ rotate(value, 19) ~ (value >> 10)
            words[index] = (words[index - 16] + first + words[index - 7] + second) & MASK
        end
        local a, b, c, d = h0, h1, h2, h3
        local e, f, g, h = h4, h5, h6, h7
        for index = 1, 64 do
            local first = rotate(e, 6) ~ rotate(e, 11) ~ rotate(e, 25)
            local choice = (e & f) ~ ((~e) & g)
            local temp1 = (h + first + choice + K[index] + words[index]) & MASK
            local second = rotate(a, 2) ~ rotate(a, 13) ~ rotate(a, 22)
            local majority = (a & b) ~ (a & c) ~ (b & c)
            local temp2 = (second + majority) & MASK
            h, g, f, e = g, f, e, (d + temp1) & MASK
            d, c, b, a = c, b, a, (temp1 + temp2) & MASK
        end
        h0 = (h0 + a) & MASK
        h1 = (h1 + b) & MASK
        h2 = (h2 + c) & MASK
        h3 = (h3 + d) & MASK
        h4 = (h4 + e) & MASK
        h5 = (h5 + f) & MASK
        h6 = (h6 + g) & MASK
        h7 = (h7 + h) & MASK
    end
    return string.pack(">I4I4I4I4I4I4I4I4", h0, h1, h2, h3, h4, h5, h6, h7)
end

local function hexRaw(raw)
    local result = {}
    for index = 1, #raw do
        result[index] = string.format("%02x", raw:byte(index))
    end
    return table.concat(result)
end

function M.hex(data)
    return hexRaw(M.raw(data))
end

function M.encode(data)
    if type(data) ~= "string" then
        error("hex input must be a string", 2)
    end
    return hexRaw(data)
end

local function hmacRaw(key, data)
    if type(key) ~= "string" or type(data) ~= "string" then
        error("HMAC key and input must be strings", 2)
    end
    if #key > 64 then
        key = M.raw(key)
    end
    key = key .. string.rep("\0", 64 - #key)
    local inner = {}
    local outer = {}
    for index = 1, 64 do
        local value = key:byte(index)
        inner[index] = string.char(value ~ 0x36)
        outer[index] = string.char(value ~ 0x5C)
    end
    return M.raw(table.concat(outer) .. M.raw(table.concat(inner) .. data))
end

function M.hmac(key, data)
    return hexRaw(hmacRaw(key, data))
end

function M.pbkdf2(password, salt, iterations, length)
    if type(password) ~= "string" or type(salt) ~= "string" then
        error("PBKDF2 password and salt must be strings", 2)
    end
    if type(iterations) ~= "number" or iterations % 1 ~= 0 or iterations < 1 then
        error("PBKDF2 iterations must be a positive integer", 2)
    end
    if type(length) ~= "number" or length % 1 ~= 0 or length < 1 then
        error("PBKDF2 length must be a positive integer", 2)
    end
    local result = {}
    local produced = 0
    local block = 1
    while produced < length do
        local u = hmacRaw(password, salt .. string.pack(">I4", block))
        local accumulator = { u:byte(1, #u) }
        for _ = 2, iterations do
            u = hmacRaw(password, u)
            for index = 1, #u do
                accumulator[index] = accumulator[index] ~ u:byte(index)
            end
        end
        for index = 1, #accumulator do
            produced = produced + 1
            if produced > length then
                break
            end
            result[produced] = string.char(accumulator[index])
        end
        block = block + 1
    end
    return table.concat(result)
end

return M
