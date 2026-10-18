local M = {}

local function walk(node, visitor)
    if type(node) ~= "table" then
        return
    end
    if node.tag then
        visitor(node)
        for key, value in pairs(node) do
            if key ~= "decl" and key ~= "selfName" and type(value) == "table" then
                walk(value, visitor)
            end
        end
    else
        for _, value in pairs(node) do
            if type(value) == "table" then
                walk(value, visitor)
            end
        end
    end
end

function M.apply(ast, context)
    if context.options.numbers_to_expressions == false then
        return
    end
    local rand = context.rand
    walk(ast, function(node)
        if node.tag ~= "number" or node.generated then
            return
        end
        local value = tonumber(node.value)
        if not value or math.type(value) ~= "integer" or value < -2000000000 or value > 2000000000 then
            return
        end
        local mask = 1 + rand() % 2147483646
        local encoded = value ~ mask
        local left = { tag = "number", value = tostring(encoded), generated = true }
        local right = { tag = "number", value = tostring(mask), generated = true }
        node.tag = "paren"
        node.exp = { tag = "binop", op = "~", left = left, right = right, generated = true }
        node.value = nil
        node.generated = true
    end)
end

return M
