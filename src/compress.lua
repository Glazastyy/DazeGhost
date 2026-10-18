local M = {}

local function hash(data)
    local value = 2166136261
    for i = 1, #data do
        value = ((value ~ data:byte(i)) * 16777619) & 0xFFFFFFFF
    end
    return value
end

local function hash3(data, index)
    return (data:byte(index) * 257 + data:byte(index + 1) * 17 + data:byte(index + 2)) & 0xFFFF
end

local function literal(emit, data, start, length)
    while length > 0 do
        local size = math.min(length, 128)
        emit(string.char(size - 1))
        emit(data:sub(start, start + size - 1))
        start = start + size
        length = length - size
    end
end

function M.pack(data)
    if type(data) ~= "string" then
        error("data must be a string", 2)
    end
    local chunks = {}
    local chunk = {}
    local chunkSize = 0
    local function emit(value)
        chunkSize = chunkSize + 1
        chunk[chunkSize] = value
        if chunkSize == 256 then
            chunks[#chunks + 1] = table.concat(chunk)
            chunk = {}
            chunkSize = 0
        end
    end
    local previous = {}
    local position = 1
    local literalStart = 1
    local literalLength = 0
    while position <= #data do
        local matchPosition
        local matchLength = 0
        if position + 2 <= #data then
            local slot = hash3(data, position)
            matchPosition = previous[slot]
            previous[slot] = position
            if matchPosition and position - matchPosition <= 65535 then
                local length = 0
                while length < 130 and position + length <= #data
                    and data:byte(matchPosition + length) == data:byte(position + length) do
                    length = length + 1
                end
                if length >= 3 then
                    matchLength = length
                else
                    matchPosition = nil
                end
            end
        end
        if matchLength > 0 then
            literal(emit, data, literalStart, literalLength)
            local remaining = matchLength
            local offset = 0
            while remaining > 0 do
                local size = math.min(remaining, 130)
                emit(string.char(128 + size - 3))
                local distance = position - matchPosition
                emit(string.char(distance & 255, (distance >> 8) & 255))
                for index = 1, size - 1 do
                    if position + offset + index + 2 <= #data then
                        previous[hash3(data, position + offset + index)] = position + offset + index
                    end
                end
                offset = offset + size
                remaining = remaining - size
            end
            position = position + matchLength
            literalStart = position
            literalLength = 0
        else
            position = position + 1
            literalLength = literalLength + 1
        end
    end
    literal(emit, data, literalStart, literalLength)
    if chunkSize > 0 then
        chunks[#chunks + 1] = table.concat(chunk)
    end
    return table.concat(chunks)
end

function M.unpack(data)
    if type(data) ~= "string" then
        error("data must be a string", 2)
    end
    local output = {}
    local producedTotal = 0
    local index = 1
    local length = #data
    while index <= length do
        local token = data:byte(index)
        index = index + 1
        if token < 128 then
            local size = token + 1
            if index + size - 1 > length then
                error("invalid compressed data", 2)
            end
            for position = index, index + size - 1 do
                producedTotal = producedTotal + 1
                output[producedTotal] = string.char(data:byte(position))
            end
            index = index + size
        else
            local size = (token & 127) + 3
            if index + 1 > length then
                error("invalid compressed data", 2)
            end
            local distance = data:byte(index) | (data:byte(index + 1) << 8)
            index = index + 2
            for _ = 1, size do
                local position = producedTotal - distance + 1
                if distance < 1 or position < 1 or not output[position] then
                    error("invalid compressed distance", 2)
                end
                producedTotal = producedTotal + 1
                output[producedTotal] = output[position]
            end
        end
    end
    return table.concat(output)
end

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64(data)
    local output = {}
    local chunk = {}
    local chunkSize = 0
    local function emit(value)
        chunkSize = chunkSize + 1
        chunk[chunkSize] = value
        if chunkSize == 4096 then
            output[#output + 1] = table.concat(chunk)
            chunk = {}
            chunkSize = 0
        end
    end
    for index = 1, #data, 3 do
        local a = data:byte(index)
        local b = data:byte(index + 1) or 0
        local c = data:byte(index + 2) or 0
        local value = a * 0x10000 + b * 0x100 + c
        local first = (value >> 18) & 63
        local second = (value >> 12) & 63
        local third = (value >> 6) & 63
        local fourth = value & 63
        emit(ALPHABET:sub(first + 1, first + 1))
        emit(ALPHABET:sub(second + 1, second + 1))
        emit(index + 1 <= #data and ALPHABET:sub(third + 1, third + 1) or "=")
        emit(index + 2 <= #data and ALPHABET:sub(fourth + 1, fourth + 1) or "=")
    end
    if chunkSize > 0 then
        output[#output + 1] = table.concat(chunk)
    end
    return table.concat(output)
end

function M.wrap(data)
    if type(data) ~= "string" then
        error("data must be a string", 2)
    end
    local packed = M.pack(data)
    local checksum = hash(data)
    local encoded = base64(packed)
    return table.concat({
        "return(function(S,E)local A='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';local R={};for j=1,#A do R[A:sub(j,j)]=j-1 end;local P={};for j=1,#S,4 do local a=R[S:sub(j,j)];local b=R[S:sub(j+1,j+1)];local c=S:sub(j+2,j+2);local d=S:sub(j+3,j+3);local x=(a<<18)|(b<<12)|((c=='=' and 0 or R[c]<<6))|(d=='=' and 0 or R[d]);P[#P+1]=string.char((x>>16)&255);if c~='=' then P[#P+1]=string.char((x>>8)&255) end;if d~='=' then P[#P+1]=string.char(x&255) end end;local C=table.concat(P);local O={};local n=0;local i=1;while i<=#C do local t=C:byte(i);i=i+1;if t<128 then local z=t+1;for k=1,z do n=n+1;O[n]=string.char(C:byte(i));i=i+1 end else local z=(t&127)+3;local d=C:byte(i)|(C:byte(i+1)<<8);i=i+2;for k=1,z do local p=n-d+1;local value=O[p];if not value then error('invalid compressed data') end;n=n+1;O[n]=value end end end;local data=table.concat(O);local h=2166136261;for k=1,#data do h=((h~data:byte(k))*16777619)&0xFFFFFFFF end;if h~=E then error('compressed payload integrity check failed') end;local fn,err=load(data,nil,'t');if not fn then error(err) end;return fn() end)(",
        string.format("%q", encoded), ",", tostring(checksum), ")"
    })
end

return M
