local M = {}

local MASK = 0xFFFFFFFF

local function mix(value)
    value = (value ~ 0x9E3779B9) & MASK
    value = ((value ~ (value >> 16)) * 0x85EBCA6B) & MASK
    value = ((value ~ (value >> 13)) * 0xC2B2AE35) & MASK
    return (value ~ (value >> 16)) & MASK
end

local function entropy()
    local file = io.open("/dev/urandom", "rb")
    if file then
        local data = file:read(16)
        file:close()
        if data and #data == 16 then
            return { string.unpack("<I4I4I4I4", data) }
        end
    end
    local time = os.time() & MASK
    local clock = math.floor(os.clock() * 1000000) & MASK
    local random = math.random(0, 0x7FFFFFFF) & MASK
    return {
        mix(time ~ clock),
        mix(clock ~ random),
        mix(random ~ time),
        mix(time ~ clock ~ random)
    }
end

local function expand(seed)
    if seed == nil then
        return entropy()
    end
    if type(seed) == "number" then
        local value = seed & MASK
        return {
            mix(value),
            mix(value ~ 0xA341316C),
            mix(value ~ 0xC8013EA4),
            mix(value ~ 0xAD90777D)
        }
    end
    if type(seed) == "table" and #seed == 4 then
        local result = {}
        for i = 1, 4 do
            if type(seed[i]) ~= "number" then
                error("seed words must be integers", 3)
            end
            result[i] = seed[i] & MASK
        end
        return result
    end
    error("seed must be an integer or four 32-bit words", 3)
end

function M.new(seed)
    local state = expand(seed)
    if state[1] == 0 and state[2] == 0 and state[3] == 0 and state[4] == 0 then
        state[4] = 0x9E3779B9
    end
    return function(minimum, maximum)
        local t = (state[1] ~ ((state[1] << 11) & MASK)) & MASK
        state[1], state[2], state[3] = state[2], state[3], state[4]
        state[4] = (state[4] ~ (state[4] >> 19) ~ t ~ (t >> 8)) & MASK
        local value = state[4]
        if minimum ~= nil then
            return minimum + value % (maximum - minimum + 1)
        end
        return value
    end
end

return M
