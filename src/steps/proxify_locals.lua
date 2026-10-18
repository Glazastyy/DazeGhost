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

local function proxyAccess(proxy, index)
    return {
        tag = "index",
        object = { tag = "name", value = proxy, fixed = true, generated = true },
        index = { tag = "number", value = tostring(index), generated = true },
        generated = true
    }
end

local function findLocal(node, result)
    if type(node) ~= "table" then
        return
    end
    if node.tag == "name" and node.decl then
        result[node.decl] = true
    end
    for _, value in pairs(node) do
        if type(value) == "table" then
            findLocal(value, result)
        end
    end
end

function M.apply(ast, context)
    if context.options.proxify_locals == false then
        return
    end
    local declarations = {}
    local declarationNodes = {}
    local excluded = {}
    walk(ast, function(node)
        if node.tag == "local" and node.names then
            local eligible = true
            for _, name in ipairs(node.names) do
                if name.attr ~= nil or name.decl == nil or name.value == "_ENV" then
                    eligible = false
                    break
                end
            end
            if eligible then
                for _, name in ipairs(node.names) do
                    declarations[name.decl] = true
                    declarationNodes[name] = true
                end
            end
        elseif node.tag == "localfunction" and node.name and node.name.attr == nil and node.name.decl then
            declarations[node.name.decl] = true
            declarationNodes[node.name] = true
        elseif node.tag == "functionstat" and node.name and node.name.object then
            findLocal(node.name.object, excluded)
        end
    end)
    for declaration in pairs(excluded) do
        declarations[declaration] = nil
    end
    if next(declarations) == nil then
        return
    end
    local proxy = context.freshName()
    local indexes = {}
    local nextIndex = 0
    for declaration in pairs(declarations) do
        nextIndex = nextIndex + 1
        indexes[declaration] = nextIndex
    end
    walk(ast, function(node)
        if node.tag == "name" and not declarationNodes[node] and node.decl and indexes[node.decl] then
            local access = proxyAccess(proxy, indexes[node.decl])
            node.tag = access.tag
            node.object = access.object
            node.index = access.index
            node.value = nil
            node.generated = true
        end
    end)
    local function replaceBlock(block)
        local output = {}
        for _, statement in ipairs(block.stats) do
            if statement.tag == "local" then
                local vars = {}
                local eligible = true
                for _, name in ipairs(statement.names) do
                    if not indexes[name.decl] then
                        eligible = false
                        break
                    end
                    vars[#vars + 1] = proxyAccess(proxy, indexes[name.decl])
                end
                if eligible then
                    if statement.values then
                        output[#output + 1] = { tag = "assign", vars = vars, values = statement.values }
                    end
                else
                    output[#output + 1] = statement
                end
            elseif statement.tag == "localfunction" and indexes[statement.name.decl] then
                output[#output + 1] = {
                    tag = "assign",
                    vars = { proxyAccess(proxy, indexes[statement.name.decl]) },
                    values = {{ tag = "funcbody", params = statement.body.params, body = statement.body.body, method = statement.body.method }}
                }
            else
                output[#output + 1] = statement
            end
        end
        block.stats = output
    end
    local function visitBlocks(node)
        if type(node) ~= "table" then
            return
        end
        if node.tag == "block" then
            replaceBlock(node)
        end
        for _, value in pairs(node) do
            if type(value) == "table" then
                visitBlocks(value)
            end
        end
    end
    visitBlocks(ast)
    table.insert(ast.stats, 1, {
        tag = "local",
        names = {{ tag = "name", value = proxy, fixed = true }},
        values = {{ tag = "table", fields = {}}}
    })
end

return M
