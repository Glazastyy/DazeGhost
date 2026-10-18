local M = {}

local definitions = {
    compact = {
        split_strings = false,
        numbers_to_expressions = false,
        constant_array = false,
        proxify_locals = false,
        name_generator = "compact"
    },
    balanced = {
        split_strings = true,
        numbers_to_expressions = true,
        constant_array = true,
        proxify_locals = true,
        name_generator = "random"
    },
    strong = {
        split_strings = true,
        numbers_to_expressions = true,
        constant_array = true,
        proxify_locals = true,
        anti_tamper = true,
        name_generator = "random"
    }
}

local function copy(values)
    local result = {}
    for key, value in pairs(values) do
        result[key] = value
    end
    return result
end

function M.available()
    local result = {}
    for name in pairs(definitions) do
        result[#result + 1] = name
    end
    table.sort(result)
    return result
end

function M.resolve(name)
    if name == nil then
        name = "balanced"
    end
    if type(name) ~= "string" or not definitions[name] then
        error("unknown preset: " .. tostring(name), 2)
    end
    return copy(definitions[name])
end

function M.apply(options)
    if type(options) ~= "table" then
        error("options must be a table", 2)
    end
    local result = copy(options)
    local values = M.resolve(options.preset)
    for key, value in pairs(values) do
        if result[key] == nil then
            result[key] = value
        end
    end
    return result
end

return M
