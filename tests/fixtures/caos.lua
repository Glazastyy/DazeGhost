local function reverse(s)
    local out = {}
    for i = #s, 1, -1 do
        out[#out + 1] = s:sub(i, i)
    end
    return table.concat(out)
end
local function checksum(s)
    local v = 419
    for i = 1, #s do
        v = (v * 37 + s:byte(i)) & 0xFFFFFFFF
    end
    return v
end
return checksum(reverse("validated"))
