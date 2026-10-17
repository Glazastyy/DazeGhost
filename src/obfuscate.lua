local parser = require("src.parser")
local bind = require("src.bind")
local emit = require("src.emit")
local crypt = require("src.crypt")

local M = {}

local function shortName(n)
    return "_" .. n
end

local function encodeString(lit)
    local ok, inner = pcall(function()
        return assert(load("return " .. lit, nil, "t", {}))()
    end)
    if not ok or type(inner) ~= "string" then
        return lit
    end
    if #inner == 0 then
        return '""'
    end
    local parts = {}
    for i = 1, #inner do
        parts[i] = string.format("\\%03d", inner:byte(i))
    end
    return '"' .. table.concat(parts) .. '"'
end

local function walk(node, fn)
    if type(node) ~= "table" then
        return
    end
    if node.tag then
        fn(node)
    end
    for _, v in pairs(node) do
        if type(v) == "table" then
            walk(v, fn)
        end
    end
end

function M.obfuscate(src, opts)
    local ast = bind.bind(parser.parse(src))
    walk(ast, function(node)
        if node.tag == "name" and node.decl then
            node.emit = shortName(node.decl)
        elseif node.tag == "string" then
            node.value = encodeString(node.value)
        end
    end)
    return crypt.seal(emit.emit(ast), opts)
end

return M
