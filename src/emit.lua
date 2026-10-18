local M = {}

local function needsSpace(previous, current)
    if previous == "" or current == "" then
        return false
    end
    local a = previous:sub(-1)
    local b = current:sub(1, 1)
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
    if a:match("%d") and b == "." then
        return true
    end
    if a == "<" and (b == "=" or b == "<") then
        return true
    end
    if a == ">" and (b == "=" or b == ">") then
        return true
    end
    if (a == "=" or a == "~") and b == "=" then
        return true
    end
    if a == ":" and b == ":" then
        return true
    end
    return false
end

function M.emit(ast)
    local chunks = {}
    local previous = ""
    local expression
    local block
    local statement

    local function put(value)
        if value == "" then
            return
        end
        if needsSpace(previous, value) then
            chunks[#chunks + 1] = " "
        end
        chunks[#chunks + 1] = value
        previous = value
    end

    local function list(items)
        for i, item in ipairs(items) do
            if i > 1 then
                put(",")
            end
            expression(item)
        end
    end

    local function names(items)
        for i, item in ipairs(items) do
            if i > 1 then
                put(",")
            end
            put(item.emit or item.value)
            if item.attr then
                put("<")
                put(item.attr)
                put(">")
            end
        end
    end

    local function params(body)
        put("(")
        names(body.params.names)
        if body.params.vararg then
            if #body.params.names > 0 then
                put(",")
            end
            put("...")
        end
        put(")")
        block(body.body)
        put("end")
    end

    expression = function(node)
        local tag = node.tag
        if tag == "nil" then
            put("nil")
        elseif tag == "boolean" then
            put(node.value and "true" or "false")
        elseif tag == "number" or tag == "string" then
            put(node.value)
        elseif tag == "vararg" then
            put("...")
        elseif tag == "name" then
            put(node.emit or node.value)
        elseif tag == "unop" then
            put(node.op)
            expression(node.exp)
        elseif tag == "binop" then
            expression(node.left)
            put(node.op)
            expression(node.right)
        elseif tag == "paren" then
            put("(")
            expression(node.exp)
            put(")")
        elseif tag == "table" then
            put("{")
            for i, field in ipairs(node.fields) do
                if i > 1 then
                    put(",")
                end
                if field.tag == "indexfield" then
                    put("[")
                    expression(field.key)
                    put("]")
                    put("=")
                elseif field.tag == "namefield" then
                    put(field.name.value)
                    put("=")
                end
                expression(field.value)
            end
            put("}")
        elseif tag == "funcbody" then
            put("function")
            params(node)
        elseif tag == "field" then
            expression(node.object)
            put(".")
            put(node.name.value)
        elseif tag == "index" then
            expression(node.object)
            put("[")
            expression(node.index)
            put("]")
        elseif tag == "call" then
            expression(node.callee)
            put("(")
            list(node.args)
            put(")")
        elseif tag == "mcall" then
            expression(node.object)
            put(":")
            put(node.name.value)
            put("(")
            list(node.args)
            put(")")
        else
            error("unsupported expression: " .. tostring(tag))
        end
    end

    statement = function(st)
        local tag = st.tag
        if tag == "empty" then
            put(";")
        elseif tag == "break" then
            put("break")
        elseif tag == "goto" then
            put("goto")
            put(st.name.value)
        elseif tag == "label" then
            put("::")
            put(st.name.value)
            put("::")
        elseif tag == "do" then
            put("do")
            block(st.body)
            put("end")
        elseif tag == "while" then
            put("while")
            expression(st.cond)
            put("do")
            block(st.body)
            put("end")
        elseif tag == "repeat" then
            put("repeat")
            block(st.body)
            put("until")
            expression(st.cond)
        elseif tag == "if" then
            for i, clause in ipairs(st.clauses) do
                put(i == 1 and "if" or "elseif")
                expression(clause.cond)
                put("then")
                block(clause.body)
            end
            if st.els then
                put("else")
                block(st.els)
            end
            put("end")
        elseif tag == "fornum" then
            put("for")
            put(st.name.emit or st.name.value)
            put("=")
            expression(st.from)
            put(",")
            expression(st.to)
            if st.step then
                put(",")
                expression(st.step)
            end
            put("do")
            block(st.body)
            put("end")
        elseif tag == "forin" then
            put("for")
            names(st.names)
            put("in")
            list(st.explist)
            put("do")
            block(st.body)
            put("end")
        elseif tag == "functionstat" then
            put("function")
            if st.body.method then
                expression(st.name.object)
                put(":")
                put(st.name.name.value)
            else
                expression(st.name)
            end
            params(st.body)
        elseif tag == "localfunction" then
            put("local function")
            put(st.name.emit or st.name.value)
            params(st.body)
        elseif tag == "local" then
            put("local")
            names(st.names)
            if st.values then
                put("=")
                list(st.values)
            end
        elseif tag == "assign" then
            list(st.vars)
            put("=")
            list(st.values)
        elseif tag == "callstat" then
            expression(st.call)
        elseif tag == "return" then
            put("return")
            if st.explist then
                list(st.explist)
            end
        else
            error("unsupported statement: " .. tostring(tag))
        end
    end

    block = function(node)
        for i, st in ipairs(node.stats) do
            if i > 1 then
                put(";")
            end
            statement(st)
        end
    end

    block(ast)
    return table.concat(chunks)
end

return M
