local M = {}

local function literalValue(literal)
    local fn = load("return " .. literal, "=split_string", "t", {})
    if not fn then
        return nil
    end
    local ok, result = pcall(fn)
    if ok and type(result) == "string" then
        return result
    end
    return nil
end

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

local function stringNode(value)
    return { tag = "string", value = string.format("%q", value), generated = true }
end

function M.apply(ast, context)
    if context.options.split_strings == false then
        return
    end
    local minimum = context.options.split_min_length or 6
    if type(minimum) ~= "number" or minimum % 1 ~= 0 or minimum < 2 then
        error("split_min_length must be an integer greater than or equal to 2", 3)
    end
    local rand = context.rand
    walk(ast, function(node)
        if node.tag ~= "string" or node.generated then
            return
        end
        local value = literalValue(node.value)
        if value == nil or #value < minimum then
            return
        end
        local pieces = {}
        local position = 1
        while position <= #value do
            local remaining = #value - position + 1
            local size = math.min(remaining, 2 + rand() % math.min(8, remaining))
            pieces[#pieces + 1] = stringNode(value:sub(position, position + size - 1))
            position = position + size
        end
        local result = pieces[1]
        for index = 2, #pieces do
            result = { tag = "binop", op = "..", left = result, right = pieces[index] }
        end
        if #pieces == 1 then
            node.value = result.value
            node.generated = true
            return
        end
        node.tag = result.tag
        node.op = result.op
        node.left = result.left
        node.right = result.right
        node.value = nil
        node.generated = true
    end)
end

return M
