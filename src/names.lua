local M = {}

local identifierStart = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local identifierBody = identifierStart .. "0123456789"
local reserved = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
    ["end"] = true, ["false"] = true, ["for"] = true, ["function"] = true, ["goto"] = true,
    ["if"] = true, ["in"] = true, ["local"] = true, ["nil"] = true, ["not"] = true,
    ["or"] = true, ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
    ["until"] = true, ["while"] = true
}

local generators = {}

local function randomIdentifier(rand, minimum, maximum)
    local length = minimum + rand(0, maximum - minimum)
    local result = {}
    local first = rand(1, #identifierStart)
    result[1] = identifierStart:sub(first, first)
    for index = 2, length do
        local position = rand(1, #identifierBody)
        result[index] = identifierBody:sub(position, position)
    end
    return table.concat(result)
end

local function random(rand)
    return randomIdentifier(rand, 12, 20)
end

local function compact(rand)
    return randomIdentifier(rand, 6, 10)
end

local function validate(name)
    if type(name) ~= "string" or not name:match("^[A-Za-z_][A-Za-z0-9_]*$") or reserved[name] then
        error("name generator returned an invalid Lua identifier", 4)
    end
end

generators.random = random
generators.compact = compact
generators.mangled = random

function M.register(name, generator)
    if type(name) ~= "string" or not name:match("^[a-z][a-z0-9_]*$") then
        error("name generator name must be lowercase snake case", 2)
    end
    if type(generator) ~= "function" then
        error("name generator must be a function", 2)
    end
    generators[name] = generator
end

function M.available()
    local result = {}
    for name in pairs(generators) do
        result[#result + 1] = name
    end
    table.sort(result)
    return result
end

function M.new(specification, rand, used)
    local generator = specification or "random"
    if type(generator) == "string" then
        generator = generators[generator]
        if not generator then
            error("unknown name generator: " .. tostring(specification), 2)
        end
    end
    if type(generator) ~= "function" then
        error("name_generator must be a registered name or function", 2)
    end
    if type(rand) ~= "function" or type(used) ~= "table" then
        error("name generator requires a random source and a used-name set", 2)
    end
    return function()
        local name = generator(rand, used)
        validate(name)
        if used[name] then
            error("name generator returned a duplicate identifier: " .. name, 3)
        end
        used[name] = true
        return name
    end
end

return M
