local M = {}

local function needsSpace(prev, nexts)
    if not prev or prev == "" or not nexts or nexts == "" then
        return false
    end
    local a = prev:sub(-1)
    local b = nexts:sub(1, 1)
    if a:match("[%w_]") and b:match("[%w_]") then
        return true
    end
    if a == "-" and b == "-" then
        return true
    end
    if a == "/" and b == "/" then
        return true
    end
    if a == "." and b == "." then
        return true
    end
    if a == "<" and (b == "=" or b == "<") then
        return true
    end
    if a == ">" and (b == "=" or b == ">") then
        return true
    end
    if a == "=" and b == "=" then
        return true
    end
    if a == "~" and b == "=" then
        return true
    end
    if a:match("%d") and b == "." then
        if not prev:match("[%a_]") then
            return true
        end
    end
    return false
end

local buf
local emitExp, emitBlock, emitStat

local function emit(s)
    if s == "" then
        return
    end
    if needsSpace(buf[#buf], s) then
        buf[#buf + 1] = " "
    end
    buf[#buf + 1] = s
end

local function emitList(list, sep)
    for i, item in ipairs(list) do
        if i > 1 then
            emit(sep)
        end
        emitExp(item)
    end
end

local function emitNames(names)
    for i, n in ipairs(names) do
        if i > 1 then
            emit(",")
        end
        emit(n.emit or n.value)
        if n.attr then
            emit("<")
            emit(n.attr)
            emit(">")
        end
    end
end

local function emitParams(body)
    emit("(")
    if body.method then
        local selfn = body.selfName
        emit((selfn and (selfn.emit or selfn.value)) or "self")
        if #body.params.names > 0 then
            emit(",")
        end
    end
    emitNames(body.params.names)
    if body.params.vararg then
        if #body.params.names > 0 or body.method then
            emit(",")
        end
        emit("...")
    end
    emit(")")
    emitBlock(body.body)
    emit("end")
end

emitExp = function(node)
    local tag = node.tag
    if tag == "nil" then
        emit("nil")
    elseif tag == "boolean" then
        emit(node.value and "true" or "false")
    elseif tag == "number" or tag == "string" then
        emit(node.value)
    elseif tag == "vararg" then
        emit("...")
    elseif tag == "name" then
        emit(node.emit or node.value)
    elseif tag == "unop" then
        emit(node.op)
        emitExp(node.exp)
    elseif tag == "binop" then
        emitExp(node.left)
        emit(node.op)
        emitExp(node.right)
    elseif tag == "paren" then
        emit("(")
        emitExp(node.exp)
        emit(")")
    elseif tag == "table" then
        emit("{")
        for i, f in ipairs(node.fields) do
            if i > 1 then
                emit(",")
            end
            if f.tag == "indexfield" then
                emit("[")
                emitExp(f.key)
                emit("]")
                emit("=")
                emitExp(f.value)
            elseif f.tag == "namefield" then
                emit(f.name.value)
                emit("=")
                emitExp(f.value)
            else
                emitExp(f.value)
            end
        end
        emit("}")
    elseif tag == "funcbody" then
        emit("function")
        emitParams(node)
    elseif tag == "field" then
        emitExp(node.object)
        emit(".")
        emit(node.name.value)
    elseif tag == "index" then
        emitExp(node.object)
        emit("[")
        emitExp(node.index)
        emit("]")
    elseif tag == "call" then
        emitExp(node.callee)
        emit("(")
        emitList(node.args, ",")
        emit(")")
    elseif tag == "mcall" then
        emitExp(node.object)
        emit(":")
        emit(node.name.value)
        emit("(")
        emitList(node.args, ",")
        emit(")")
    else
        error("emit exp " .. tostring(tag))
    end
end

emitStat = function(st)
    local tag = st.tag
    if tag == "empty" then
        emit(";")
    elseif tag == "break" then
        emit("break")
    elseif tag == "goto" then
        emit("goto")
        emit(st.name.value)
    elseif tag == "label" then
        emit("::")
        emit(st.name.value)
        emit("::")
    elseif tag == "do" then
        emit("do")
        emitBlock(st.body)
        emit("end")
    elseif tag == "while" then
        emit("while")
        emitExp(st.cond)
        emit("do")
        emitBlock(st.body)
        emit("end")
    elseif tag == "repeat" then
        emit("repeat")
        emitBlock(st.body)
        emit("until")
        emitExp(st.cond)
    elseif tag == "if" then
        for i, c in ipairs(st.clauses) do
            emit(i == 1 and "if" or "elseif")
            emitExp(c.cond)
            emit("then")
            emitBlock(c.body)
        end
        if st.els then
            emit("else")
            emitBlock(st.els)
        end
        emit("end")
    elseif tag == "fornum" then
        emit("for")
        emit(st.name.emit or st.name.value)
        emit("=")
        emitExp(st.from)
        emit(",")
        emitExp(st.to)
        if st.step then
            emit(",")
            emitExp(st.step)
        end
        emit("do")
        emitBlock(st.body)
        emit("end")
    elseif tag == "forin" then
        emit("for")
        emitNames(st.names)
        emit("in")
        emitList(st.explist, ",")
        emit("do")
        emitBlock(st.body)
        emit("end")
    elseif tag == "functionstat" then
        emit("function")
        emitExp(st.name)
        emitParams(st.body)
    elseif tag == "localfunction" then
        emit("local function")
        emit(st.name.emit or st.name.value)
        emitParams(st.body)
    elseif tag == "local" then
        emit("local")
        emitNames(st.names)
        if st.values then
            emit("=")
            emitList(st.values, ",")
        end
    elseif tag == "assign" then
        emitList(st.vars, ",")
        emit("=")
        emitList(st.values, ",")
    elseif tag == "callstat" then
        emitExp(st.call)
    elseif tag == "return" then
        emit("return")
        if st.explist then
            emitList(st.explist, ",")
        end
    else
        error("emit stat " .. tostring(tag))
    end
end

emitBlock = function(block)
    for _, st in ipairs(block.stats) do
        emitStat(st)
    end
end

function M.emit(ast)
    buf = {}
    emitBlock(ast)
    return table.concat(buf)
end

return M
