local parser = require("src.parser")
local bind = require("src.bind")
local emit = require("src.emit")
local crypt = require("src.crypt")
local weave = require("src.weave")
local random128 = require("src.random")
local compress = require("src.compress")
local pipeline = require("src.pipeline")

local M = {}

local MASK = 0xFFFFFFFF

local function hash(s)
    local value = 2166136261
    for i = 1, #s do
        value = ((value ~ s:byte(i)) * 16777619) & MASK
    end
    return value
end

local function walk(node, visitor)
    if type(node) ~= "table" then
        return
    end
    if node.tag then
        for key, value in pairs(node) do
            if key ~= "decl" and key ~= "selfName" and type(value) == "table" then
                walk(value, visitor)
            end
        end
        visitor(node)
    else
        for _, value in pairs(node) do
            if type(value) == "table" then
                walk(value, visitor)
            end
        end
    end
end

local function literalValue(literal)
    local fn = load("return " .. literal, "=string_literal", "t", {})
    if not fn then
        return nil
    end
    local ok, result = pcall(fn)
    if ok and type(result) == "string" then
        return result
    end
    return nil
end

local function identifiers(ast)
    local used = {}
    walk(ast, function(node)
        if node.tag == "name" then
            used[node.value] = true
        end
    end)
    return used
end

local function freshName(used, rand)
    while true do
        local name = string.format("_dg%08x", rand())
        if not used[name] then
            used[name] = true
            return name
        end
    end
end

local function protectStrings(ast, name, rand)
    local changed = false
    walk(ast, function(node)
        if node.tag ~= "string" then
            return
        end
        local value = literalValue(node.value)
        if value == nil then
            error("invalid Lua string literal")
        end
        local key = rand() & 255
        local bytes = {}
        for i = 1, #value do
            bytes[i] = string.format("\\%03d", (value:byte(i) ~ ((key + i * 73) & 255)) & 255)
        end
        node.tag = "call"
        node.value = nil
        node.callee = { tag = "name", value = name }
        node.args = {
            { tag = "string", value = '"' .. table.concat(bytes) .. '"' },
            { tag = "number", value = tostring(key) }
        }
        changed = true
    end)
    return changed
end

local function flattenBlock(block, name, rand)
    local function process(st)
        if st.tag == "if" then
            for _, clause in ipairs(st.clauses) do
                flattenBlock(clause.body, name, rand)
            end
            if st.els then
                flattenBlock(st.els, name, rand)
            end
        elseif st.tag == "funcbody" then
            flattenBlock(st.body, name, rand)
        elseif st.tag == "functionstat" or st.tag == "localfunction" then
            flattenBlock(st.body.body, name, rand)
        elseif st.tag == "while" or st.tag == "do" or st.tag == "repeat" or st.tag == "fornum" or st.tag == "forin" then
            flattenBlock(st.body, name, rand)
        end
    end
    for _, st in ipairs(block.stats) do
        process(st)
    end
    local output = {}
    local i = 1
    while i <= #block.stats do
        local group = {}
        while i <= #block.stats and (block.stats[i].tag == "callstat" or block.stats[i].tag == "assign") do
            group[#group + 1] = block.stats[i]
            i = i + 1
        end
        if #group >= 3 then
            local states = {}
            local used = {}
            for j = 1, #group do
                local value
                repeat
                    value = rand() % 2147483647 + 1
                until not used[value]
                used[value] = true
                states[j] = value
            end
            local clauses = {}
            for j, original in ipairs(group) do
                local condition = {
                    tag = "binop", op = "==",
                    left = { tag = "name", value = name },
                    right = { tag = "number", value = tostring(states[j]) }
                }
                local target = j == #group and 0 or states[j + 1]
                clauses[j] = {
                    cond = condition,
                    body = { tag = "block", stats = {
                        original,
                        { tag = "assign", vars = { { tag = "name", value = name } }, values = { { tag = "number", value = tostring(target) } } }
                    } }
                }
            end
            output[#output + 1] = {
                tag = "do",
                body = { tag = "block", stats = {
                    { tag = "local", names = { { tag = "name", value = name } }, values = { { tag = "number", value = tostring(states[1]) } } },
                    { tag = "while", cond = { tag = "boolean", value = true }, body = {
                        tag = "block", stats = {
                            { tag = "if", clauses = clauses, els = { tag = "block", stats = { { tag = "break" } } } }
                        }
                    } }
                } }
            }
        else
            for _, original in ipairs(group) do
                output[#output + 1] = original
            end
        end
        if i <= #block.stats then
            output[#output + 1] = block.stats[i]
            i = i + 1
        end
    end
    block.stats = output
end

function M.transform(src, opts)
    opts = opts or {}
    if type(src) ~= "string" then
        error("source must be a string", 2)
    end
    if opts.anti_ia then
        src = weave.weave(src, opts)
    end
    local ast = bind.bind(parser.parse(src))
    local used = identifiers(ast)
    local mapping = {}
    local initial
    if opts.seed ~= nil then
        initial = (opts.seed ~ hash(src)) & MASK
    end
    local rand = random128.new(initial)
    local context = {
        options = opts,
        rand = rand,
        freshName = function()
            return freshName(used, rand)
        end
    }
    pipeline.run(ast, context, opts.steps)
    if opts.rename_locals ~= false then
        walk(ast, function(node)
            if node.tag == "name" and node.decl and not node.fixed then
                if not mapping[node.decl] then
                    mapping[node.decl] = freshName(used, rand)
                end
                node.emit = mapping[node.decl]
            end
        end)
    end
    local prefix = ""
    if opts.anti_tamper == true then
        local guard = freshName(used, rand)
        prefix = "local " .. guard .. "=(function()local d=debug;if d and type(d.gethook)=='function' and d.gethook()~=nil then return false end;return true end)();if not " .. guard .. " then error('runtime integrity check failed') end;"
    end
    if opts.encode_strings ~= false then
        local helper = freshName(used, rand)
        if protectStrings(ast, helper, rand) then
            prefix = "local " .. helper .. "=(function()local c,t=string.char,table.concat;return function(s,k)local a={};for i=1,#s do a[i]=c((s:byte(i)~((k+i*73)&255))&255)end;return t(a)end end)();"
        end
    end
    if opts.flatten ~= false then
        local state = freshName(used, rand)
        flattenBlock(ast, state, rand)
    end
    local transformed = prefix .. emit.emit(ast)
    local compiled, err = load(transformed, "=transformed", "t")
    if not compiled then
        error("transformed code is invalid: " .. tostring(err), 2)
    end
    return transformed
end

function M.obfuscate(src, opts)
    opts = opts or {}
    if type(src) ~= "string" then
        error("source must be a string", 2)
    end
    if type(opts) ~= "table" then
        error("options must be a table", 2)
    end
    local rounds = opts.rounds or 1
    if type(rounds) ~= "number" or rounds % 1 ~= 0 or rounds < 1 or rounds > 5 then
        error("rounds must be an integer between 1 and 5", 2)
    end
    local maximum = opts.max_output_bytes or 12 * 1024 * 1024
    if type(maximum) ~= "number" or maximum % 1 ~= 0 or maximum < 1024 then
        error("max_output_bytes must be an integer greater than or equal to 1024", 2)
    end
    local intermediateMaximum = opts.max_intermediate_bytes or math.max(maximum * 8, 64 * 1024 * 1024)
    if type(intermediateMaximum) ~= "number" or intermediateMaximum % 1 ~= 0 or intermediateMaximum < maximum then
        error("max_intermediate_bytes must be an integer greater than or equal to max_output_bytes", 2)
    end
    local original = src
    local current = src
    local transformEachRound = opts.transform_each_round == true
    for round = 1, rounds do
        local step = {}
        for key, value in pairs(opts) do
            step[key] = value
        end
        if opts.seed ~= nil then
            step.seed = (opts.seed + (round - 1) * 0x9E3779B9) & MASK
        end
        if round > 1 and opts.anti_ia == true and opts.mix_original ~= false then
            step.original_src = original
        else
            step.original_src = nil
        end
        if opts.min_chunk_size == nil then
            step.min_chunk_size = round == 1 and 24 or 96
        end
        if opts.max_chunk_size == nil then
            step.max_chunk_size = round == 1 and 80 or 256
        end
        if opts.noise_density == nil then
            step.noise_density = round == 1 and 25 or 8
        end
        local transformed
        if round == 1 or transformEachRound then
            transformed = M.transform(current, step)
        else
            transformed = current
        end
        if #transformed > intermediateMaximum then
            error("maximum intermediate size exceeded during transformation at round " .. round, 2)
        end
        step._decoy_woven = true
        current = crypt.seal(transformed, step)
        if opts.compress_rounds == true then
            local compressed = compress.wrap(current)
            if #compressed < #current then
                current = compressed
            end
        end
        if opts.stage_writer ~= nil then
            if type(opts.stage_writer) ~= "function" then
                error("stage_writer must be a function", 2)
            end
            current = opts.stage_writer(current, round)
            if type(current) ~= "string" then
                error("stage_writer must return a string", 2)
            end
        end
        if #current > maximum then
            error("maximum output size exceeded during sealing at round " .. round, 2)
        end
    end
    return current
end

return M
