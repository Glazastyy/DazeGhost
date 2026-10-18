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

local function clone(node)
    return { tag = node.tag, value = node.value }
end

function M.apply(ast, context)
    if context.options.constant_array == false then
        return
    end
    local values = {}
    local indexes = {}
    local poolName = context.freshName()
    local changed = false
    walk(ast, function(node)
        if node.generated or (node.tag ~= "string" and node.tag ~= "number") then
            return
        end
        local key = node.tag .. ":" .. node.value
        local index = indexes[key]
        if not index then
            index = #values + 1
            indexes[key] = index
            values[index] = clone(node)
        end
        node.tag = "index"
        node.object = { tag = "name", value = poolName, fixed = true, generated = true }
        node.index = { tag = "number", value = tostring(index), generated = true }
        node.value = nil
        node.generated = true
        changed = true
    end)
    if not changed then
        return
    end
    table.insert(ast.stats, 1, {
        tag = "local",
        names = {{ tag = "name", value = poolName, fixed = true }},
        values = {{ tag = "table", fields = (function()
            local fields = {}
            for index, value in ipairs(values) do
                fields[index] = { tag = "listfield", value = value }
            end
            return fields
        end)()}}
    })
end

return M
