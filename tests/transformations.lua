local obfuscate = require("src.obfuscate")
local crypt = require("src.crypt")
local names = require("src.names")
local pipeline = require("src.pipeline")
local presets = require("src.presets")

local function execute(source, environment)
    environment = environment or _G
    local chunk, err = load(source, "=transformations", "t", environment)
    assert(chunk, err)
    return table.pack(chunk())
end

do
    local availableNames = names.available()
    assert(table.concat(availableNames, ","):find("compact", 1, true))
    assert(table.concat(availableNames, ","):find("random", 1, true))
    assert(presets.resolve("balanced").constant_array == true)
    assert(presets.resolve("compact").constant_array == false)
    assert(presets.resolve("strong").proxify_locals == true)
    local availableSteps = pipeline.available()
    assert(table.concat(availableSteps, ","):find("constant_array", 1, true))
    assert(#pipeline.defaults() == 5)
end

do
    local count = 0
    local output = obfuscate.transform("local original_name=4;return original_name", {
        encode_strings = false,
        split_strings = false,
        numbers_to_expressions = false,
        constant_array = false,
        proxify_locals = false,
        flatten = false,
        name_generator = function()
            count = count + 1
            return "customName" .. count
        end,
        seed = 31
    })
    assert(output:find("customName1", 1, true))
    assert(not output:find("original_name", 1, true))
end

do
    local registered = "registered_stage_for_test"
    pipeline.register(registered, function(ast, context)
        context.options.registered_stage_used = true
        ast.stats[1] = { tag = "return", explist = {{ tag = "number", value = "11" }} }
    end)
    local output = obfuscate.transform("return 3", {
        steps = { registered },
        encode_strings = false,
        flatten = false,
        rename_locals = false
    })
    assert(execute(output)[1] == 11)
end

do
    local ok, message = pcall(function()
        obfuscate.transform("return 3", { steps = { "missing_stage" } })
    end)
    assert(not ok)
    assert(tostring(message):find("unknown transformation step", 1, true))
end

do
    local compact = obfuscate.transform("local value=12345;return value", {
        preset = "compact",
        encode_strings = false,
        flatten = false
    })
    assert(compact:find("12345", 1, true))
    local balanced = obfuscate.transform("local value=12345;return value", {
        preset = "balanced",
        encode_strings = false,
        flatten = false
    })
    assert(not balanced:find("12345", 1, true))
end

do
    local source = [[
local first = 12345
local second = 678
return first + second
]]
    local output = obfuscate.transform(source, {
        encode_strings = false,
        split_strings = false,
        constant_array = false,
        numbers_to_expressions = true,
        flatten = false,
        seed = 17
    })
    assert(not output:find("12345", 1, true))
    assert(not output:find("678", 1, true))
    assert(execute(output)[1] == 13023)
end

do
    local source = [[
return "abcdefghij"
]]
    local output = obfuscate.transform(source, {
        encode_strings = false,
        split_strings = true,
        constant_array = false,
        numbers_to_expressions = false,
        flatten = false,
        seed = 18
    })
    assert(output:find("%.%."))
    assert(execute(output)[1] == "abcdefghij")
end

do
    local source = [[
local label = "alpha"
return label
]]
    local output = obfuscate.transform(source, {
        encode_strings = false,
        split_strings = false,
        constant_array = true,
        numbers_to_expressions = false,
        flatten = false,
        seed = 19
    })
    assert(output:find("alpha", 1, true))
    assert(output:find("%[1%]"))
    assert(execute(output)[1] == "alpha")
end

do
    local source = "return 7"
    local output = obfuscate.transform(source, {
        encode_strings = false,
        split_strings = false,
        constant_array = false,
        numbers_to_expressions = false,
        flatten = false,
        steps = {
            function(ast)
                ast.stats[1] = {
                    tag = "return",
                    explist = {{ tag = "number", value = "9" }}
                }
            end
        }
    })
    assert(execute(output)[1] == 9)
end

do
    local source = [[
local function make()
    local value = 4
    return function(step)
        value = value + step
        return value
    end
end
local nextValue = make()
return nextValue(3), nextValue(2)
]]
    local output = obfuscate.transform(source, {
        proxify_locals = true,
        split_strings = false,
        numbers_to_expressions = false,
        constant_array = false,
        flatten = false,
        seed = 22
    })
    assert(output:find("%[1%]"))
    local result = execute(output)
    assert(result[1] == 7 and result[2] == 9)
end

do
    local source = 'return "watermarked"'
    local output = obfuscate.transform(source, {
        watermark = "release-2026",
        seed = 20
    })
    assert(not output:find("release%-2026"))
    assert(execute(output)[1] == "watermarked")
end

do
    local source = 'return "native dispatch"'
    local output = crypt.seal(source, { seed = 23, mode = "text" })
    local calls = 0
    local environment = { dazeghost_load = function(data, name, mode)
        calls = calls + 1
        return assert(load(data, name, mode, environment))
    end }
    setmetatable(environment, { __index = _G })
    local result = execute(output, environment)
    assert(result[1] == "native dispatch")
    assert(calls == 1)
end

do
    local source = "return 1"
    local output = obfuscate.transform(source, {
        anti_tamper = true,
        seed = 21
    })
    local environment = { debug = { gethook = function() return function() end end } }
    setmetatable(environment, { __index = _G })
    local chunk = assert(load(output, "=anti-tamper", "t", environment))
    assert(not pcall(chunk))
    assert(execute(output)[1] == 1)
end

print("passed: transformation pipeline checks")
