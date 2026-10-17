local M = {}

local function scope(parent)
    return { parent = parent, locals = {}, n = parent and parent.n or 0 }
end

local function declare(sc, node)
    sc.n = sc.n + 1
    node.decl = sc.n
    sc.locals[node.value] = node.decl
end

local function resolve(sc, node)
    local s = sc
    while s do
        local d = s.locals[node.value]
        if d then
            node.decl = d
            return
        end
        s = s.parent
    end
    node.decl = nil
end

local function bindExp(sc, node)
    if not node then
        return
    end
    local tag = node.tag
    if tag == "name" then
        resolve(sc, node)
    elseif tag == "unop" then
        bindExp(sc, node.exp)
    elseif tag == "binop" then
        bindExp(sc, node.left)
        bindExp(sc, node.right)
    elseif tag == "paren" then
        bindExp(sc, node.exp)
    elseif tag == "table" then
        for _, f in ipairs(node.fields) do
            if f.key then
                bindExp(sc, f.key)
            end
            bindExp(sc, f.value)
            if f.name then
                -- field names stay
            end
        end
    elseif tag == "funcbody" then
        local inner = scope(sc)
        if node.method then
            local selfn = { tag = "name", value = "self" }
            declare(inner, selfn)
            node.selfName = selfn
        end
        for _, n in ipairs(node.params.names) do
            declare(inner, n)
        end
        M.bindBlock(inner, node.body)
    elseif tag == "field" then
        bindExp(sc, node.object)
    elseif tag == "index" then
        bindExp(sc, node.object)
        bindExp(sc, node.index)
    elseif tag == "call" then
        bindExp(sc, node.callee)
        for _, a in ipairs(node.args) do
            bindExp(sc, a)
        end
    elseif tag == "mcall" then
        bindExp(sc, node.object)
        for _, a in ipairs(node.args) do
            bindExp(sc, a)
        end
    end
end

local function bindStat(sc, st)
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
        for _, c in ipairs(st.clauses) do
            bindExp(sc, c.cond)
            M.bindBlock(scope(sc), c.body)
        end
        if st.els then
            M.bindBlock(scope(sc), st.els)
        end
    elseif tag == "fornum" then
        bindExp(sc, st.from)
        bindExp(sc, st.to)
        if st.step then
            bindExp(sc, st.step)
        end
        local inner = scope(sc)
        declare(inner, st.name)
        M.bindBlock(inner, st.body)
    elseif tag == "forin" then
        for _, e in ipairs(st.explist) do
            bindExp(sc, e)
        end
        local inner = scope(sc)
        for _, n in ipairs(st.names) do
            declare(inner, n)
        end
        M.bindBlock(inner, st.body)
    elseif tag == "functionstat" then
        bindExp(sc, st.name)
        bindExp(sc, st.body)
    elseif tag == "localfunction" then
        declare(sc, st.name)
        bindExp(sc, st.body)
    elseif tag == "local" then
        if st.values then
            for _, e in ipairs(st.values) do
                bindExp(sc, e)
            end
        end
        for _, n in ipairs(st.names) do
            declare(sc, n)
        end
    elseif tag == "assign" then
        for _, v in ipairs(st.vars) do
            bindExp(sc, v)
        end
        for _, e in ipairs(st.values) do
            bindExp(sc, e)
        end
    elseif tag == "callstat" then
        bindExp(sc, st.call)
    elseif tag == "return" then
        if st.explist then
            for _, e in ipairs(st.explist) do
                bindExp(sc, e)
            end
        end
    elseif tag == "goto" or tag == "label" then
        -- labels are not locals
    end
end

function M.bindBlock(sc, block)
    for _, st in ipairs(block.stats) do
        bindStat(sc, st)
    end
end

function M.bind(ast)
    M.bindBlock(scope(nil), ast)
    return ast
end

return M
