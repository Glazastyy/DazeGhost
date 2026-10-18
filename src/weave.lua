local parser = require("src.parser")
local emit = require("src.emit")
local random128 = require("src.random")

local M = {}
local MASK = 0xFFFFFFFF

local function hash(s)
    local value = 2166136261
    for i = 1, #s do
        value = ((value ~ s:byte(i)) * 16777619) & MASK
    end
    return value
end

local function readFile(path)
    local file, err = io.open(path, "rb")
    if not file then
        error("cannot open decoy file '" .. path .. "': " .. tostring(err), 3)
    end
    local content = file:read("*a")
    file:close()
    return content
end

function M.resolve(opts)
    opts = opts or {}
    if opts.decoy_path ~= nil then
        if type(opts.decoy_path) ~= "string" or opts.decoy_path == "" then
            error("decoy_path must be a nonempty filename", 2)
        end
        return readFile(opts.decoy_path)
    end
    local input = opts.decoy_src
    if input == nil then
        return [[
local function validate(token)
    local accumulator = 2166136261
    for i = 1, #token do
        accumulator = ((accumulator ~ token:byte(i)) * 16777619) & 0xFFFFFFFF
    end
    return accumulator == 0xAC142EEF
end
return validate
]]
    end
    if type(input) ~= "string" then
        error("decoy_src must be a string or a Lua file path", 2)
    end
    local file = io.open(input, "rb")
    if file then
        local data = file:read("*a")
        file:close()
        return data
    end
    if input:match("^[%w_%.%-%/\\]+%.lua$") then
        error("decoy_src file not found: " .. input, 2)
    end
    return input
end

local function examineStatement(st)
    local code = emit.emit({ tag = "block", stats = { st } })
    local fn = load("return function(...) " .. code .. " end", "=decoy_fragment", "t", {})
    if fn then
        return code
    end
    return nil
end

local function gather(block, fragments, maxFragments)
    for _, st in ipairs(block.stats) do
        if #fragments >= maxFragments then
            return
        end
        if st.tag ~= "label" and st.tag ~= "goto" and st.tag ~= "break" and st.tag ~= "empty" then
            local code = examineStatement(st)
            if code then
                fragments[#fragments + 1] = code
            end
        end
        local tag = st.tag
        if tag == "localfunction" or tag == "functionstat" then
            gather(st.body.body, fragments, maxFragments)
        elseif tag == "do" or tag == "while" or tag == "repeat" or tag == "fornum" or tag == "forin" then
            gather(st.body, fragments, maxFragments)
        elseif tag == "if" then
            for _, clause in ipairs(st.clauses) do
                gather(clause.body, fragments, maxFragments)
            end
            if st.els then
                gather(st.els, fragments, maxFragments)
            end
        end
    end
end

local function hasJump(node)
    if type(node) ~= "table" then
        return false
    end
    if node.tag == "goto" or node.tag == "label" then
        return true
    end
    for key, child in pairs(node) do
        if key ~= "line" and key ~= "col" and hasJump(child) then
            return true
        end
    end
    return false
end

local function integerExpression(value)
    local chunk = parser.parse("return " .. value)
    return chunk.stats[1].explist[1]
end

local function buildStatement(code)
    local chunk = parser.parse(code)
    return chunk.stats[1]
end

local function folded(x)
    x = ((x ~ 0x9E3779B9) * 1664525 + 1013904223) & MASK
    return ((x ~ (x >> 13)) * 2246822519) & MASK
end

local function walkNested(node, visit)
    if type(node) ~= "table" then
        return
    end
    if node.tag == "funcbody" then
        visit(node.body)
        return
    end
    if node.tag == "block" then
        visit(node)
        return
    end
    for key, value in pairs(node) do
        if key ~= "line" and key ~= "col" and type(value) == "table" then
            walkNested(value, visit)
        end
    end
end

function M.weave(src, opts)
    opts = opts or {}
    if type(src) ~= "string" then
        error("source must be a string", 2)
    end
    local decoy = M.resolve(opts)
    local decoyAst = parser.parse(decoy)
    local fragments = {}
    local limit = opts.max_decoy_fragments or 192
    if type(limit) ~= "number" or limit % 1 ~= 0 or limit < 1 or limit > 2048 then
        error("max_decoy_fragments must be an integer between 1 and 2048", 2)
    end
    gather(decoyAst, fragments, limit)
    if opts.original_src ~= nil then
        if type(opts.original_src) ~= "string" then
            error("original_src must be a string", 2)
        end
        local originalFragments = {}
        gather(parser.parse(opts.original_src), originalFragments, limit)
        local merged = {}
        local i = 1
        while #merged < limit and (i <= #fragments or i <= #originalFragments) do
            if i <= #fragments then
                merged[#merged + 1] = fragments[i]
            end
            if i <= #originalFragments and #merged < limit then
                merged[#merged + 1] = originalFragments[i]
            end
            i = i + 1
        end
        fragments = merged
    end
    if #fragments == 0 then
        error("decoy does not contain usable Lua statements", 2)
    end
    local ast = parser.parse(src)
    local seed
    if opts.seed ~= nil then
        seed = (opts.seed ~ hash(src) ~ hash(decoy)) & MASK
    end
    local rand = random128.new(seed)
    local unique = string.format("_dg_mix_%08x", rand())
    while src:find(unique, 1, true) or decoy:find(unique, 1, true) do
        unique = string.format("_dg_mix_%08x", rand())
    end
    local helper = unique .. "_f"
    local inserted = 0
    local visited = 0
    local count = #fragments
    local density = opts.decoy_density or 100
    if type(density) ~= "number" or density % 1 ~= 0 or density < 1 or density > 100 then
        error("decoy_density must be an integer between 1 and 100", 2)
    end

    local weaveBlock
    weaveBlock = function(block)
        local out = {}
        for _, st in ipairs(block.stats) do
            walkNested(st, weaveBlock)
            local eligible = not hasJump(st) and (
                st.tag == "assign" or st.tag == "callstat" or st.tag == "return"
                or st.tag == "if" or st.tag == "while" or st.tag == "fornum"
                or st.tag == "forin" or st.tag == "repeat" or st.tag == "do"
            )
            if (eligible or st.tag == "local" or st.tag == "localfunction") and rand(1, 100) <= density then
                visited = visited + 1
                local candidate = fragments[((visited - 1) % count) + 1]
                local seedValue = (hash(candidate) ~ rand()) & MASK
                local expected = folded(seedValue)
                local fake = buildStatement("local function " .. unique .. "(...) " .. candidate .. " end")
                local condition = integerExpression(helper .. "(" .. tostring(seedValue) .. ")==" .. tostring(expected))
                local guard = {
                    tag = "if",
                    clauses = { { cond = condition, body = { tag = "block", stats = eligible and { st } or {} } } },
                    els = { tag = "block", stats = { fake } }
                }
                out[#out + 1] = guard
                if not eligible then
                    out[#out + 1] = st
                end
                inserted = inserted + 1
            else
                out[#out + 1] = st
            end
        end
        block.stats = out
    end

    weaveBlock(ast)
    if inserted == 0 then
        local candidate = fragments[1]
        local number = hash(candidate)
        local expected = folded(number)
        table.insert(ast.stats, 1, {
            tag = "if",
            clauses = { { cond = integerExpression(helper .. "(" .. tostring(number) .. ")==" .. tostring(expected)), body = { tag = "block", stats = {} } } },
            els = { tag = "block", stats = { buildStatement("local function " .. unique .. "(...) " .. candidate .. " end") } }
        })
    end
    local code = emit.emit(ast)
    local helperText = "local function " .. helper .. "(x) x=((x~0x9E3779B9)*1664525+1013904223)&0xFFFFFFFF;return ((x~(x>>13))*2246822519)&0xFFFFFFFF end;"
    local output = helperText .. code
    local fn, err = load(output, "=mixed_source", "t")
    if not fn then
        error("interleaved source is invalid: " .. tostring(err), 2)
    end
    return output
end

return M
