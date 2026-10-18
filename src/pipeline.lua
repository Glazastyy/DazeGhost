local M = {}

local builtins = {
    split_strings = require("src.steps.split_strings"),
    numbers_to_expressions = require("src.steps.numbers_to_expressions"),
    constant_array = require("src.steps.constant_array"),
    watermark = require("src.steps.watermark"),
    proxify_locals = require("src.steps.proxify_locals")
}

local defaults = {
    "split_strings",
    "numbers_to_expressions",
    "constant_array",
    "proxify_locals",
    "watermark"
}

local function validateName(name)
    if type(name) ~= "string" or not name:match("^[a-z][a-z0-9_]*$") then
        error("transformation step name must be lowercase snake case", 3)
    end
end

function M.register(name, implementation)
    validateName(name)
    if type(implementation) == "function" then
        implementation = { apply = implementation }
    end
    if type(implementation) ~= "table" or type(implementation.apply) ~= "function" then
        error("transformation step must be a function or a table with apply", 2)
    end
    builtins[name] = implementation
end

local function listSteps(requested)
    if requested == nil then
        local result = {}
        for index, name in ipairs(defaults) do
            result[index] = name
        end
        return result
    end
    if type(requested) ~= "table" then
        error("steps must be a table", 3)
    end
    return requested
end

function M.resolve(requested)
    local result = {}
    for index, step in ipairs(listSteps(requested)) do
        local implementation
        if type(step) == "string" then
            implementation = builtins[step]
            if not implementation then
                error("unknown transformation step: " .. step, 3)
            end
        elseif type(step) == "function" then
            implementation = { apply = step }
        elseif type(step) == "table" and type(step.apply) == "function" then
            implementation = step
        else
            error("invalid transformation step", 3)
        end
        result[index] = implementation
    end
    return result
end

function M.run(ast, context, requested)
    for _, implementation in ipairs(M.resolve(requested)) do
        implementation.apply(ast, context)
    end
    return ast
end

function M.available()
    local result = {}
    for name in pairs(builtins) do
        result[#result + 1] = name
    end
    table.sort(result)
    return result
end

function M.defaults()
    local result = {}
    for index, name in ipairs(defaults) do
        result[index] = name
    end
    return result
end

return M
