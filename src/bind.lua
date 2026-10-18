local M = {}

local function scope(parent, state)
    return { parent = parent, state = state or parent.state, locals = {} }
end

local function declare(sc, node, fixed)
    sc.state.next = sc.state.next + 1
    node.decl = sc.state.next
    node.fixed = fixed or node.value == "_ENV" or false
    sc.locals[node.value] = { id = node.decl, fixed = node.fixed }
end

local function resolve(sc, node)
    while sc do
        local entry = sc.locals[node.value]
        if entry then
            node.decl = entry.id
            node.fixed = entry.fixed
            return
        end
        sc = sc.parent
    end
    node.decl = nil
end

local bindExp
local bindStat

bindExp = function(sc, node)
    if not node then
        return
    end
    local tag = node.tag
    if tag == "name" then
        resolve(sc, node)
    elseif tag == "unop" or tag == "paren" then
        bindExp(sc, node.exp)
    elseif tag == "binop" then
        bindExp(sc, node.left)
        bindExp(sc, node.right)
    elseif tag == "table" then
        for _, field in ipairs(node.fields) do
            bindExp(sc, field.key)
            bindExp(sc, field.value)
        end
    elseif tag == "funcbody" then
        local inner = scope(sc)
        if node.method then
            local selfName = { tag = "name", value = "self" }
            declare(inner, selfName, true)
            node.selfName = selfName
        end
        for _, param in ipairs(node.params.names) do
            declare(inner, param)
        end
        M.bindBlock(inner, node.body)
    elseif tag == "field" then
        bindExp(sc, node.object)
    elseif tag == "index" then
        bindExp(sc, node.object)
        bindExp(sc, node.index)
    elseif tag == "call" then
        bindExp(sc, node.callee)
        for _, arg in ipairs(node.args) do
            bindExp(sc, arg)
        end
    elseif tag == "mcall" then
        bindExp(sc, node.object)
        for _, arg in ipairs(node.args) do
            bindExp(sc, arg)
        end
    end
end

bindStat = function(sc, st)
    local tag = st.tag
    if tag == "do" then
        M.bindBlock(scope(sc), st.body)
    elseif tag == "while" then
        bindExp(sc, st.cond)
        M.bindBlock(scope(sc), st.body)
    elseif tag == "repeat" then
        local inner = scope(sc)
        M.bindBlock(inner, st.body)
        bindExp(inner, st.cond)
    elseif tag == "if" then
        for _, clause in ipairs(st.clauses) do
            bindExp(sc, clause.cond)
            M.bindBlock(scope(sc), clause.body)
        end
        if st.els then
            M.bindBlock(scope(sc), st.els)
        end
    elseif tag == "fornum" then
        bindExp(sc, st.from)
        bindExp(sc, st.to)
        bindExp(sc, st.step)
        local inner = scope(sc)
        declare(inner, st.name)
        M.bindBlock(inner, st.body)
    elseif tag == "forin" then
        for _, exp in ipairs(st.explist) do
            bindExp(sc, exp)
        end
        local inner = scope(sc)
        for _, name in ipairs(st.names) do
            declare(inner, name)
        end
        M.bindBlock(inner, st.body)
    elseif tag == "functionstat" then
        bindExp(sc, st.name)
        bindExp(sc, st.body)
    elseif tag == "localfunction" then
        declare(sc, st.name)
        bindExp(sc, st.body)
    elseif tag == "local" then
        for _, exp in ipairs(st.values or {}) do
            bindExp(sc, exp)
        end
        for _, name in ipairs(st.names) do
            declare(sc, name)
        end
    elseif tag == "assign" then
        for _, var in ipairs(st.vars) do
            bindExp(sc, var)
        end
        for _, exp in ipairs(st.values) do
            bindExp(sc, exp)
        end
    elseif tag == "callstat" then
        bindExp(sc, st.call)
    elseif tag == "return" then
        for _, exp in ipairs(st.explist or {}) do
            bindExp(sc, exp)
        end
    end
end

function M.bindBlock(sc, block)
    for _, st in ipairs(block.stats) do
        bindStat(sc, st)
    end
end

function M.bind(ast)
    local state = { next = 0 }
    M.bindBlock(scope(nil, state), ast)
    return ast
end

return M
