local lexer = require("src.lexer")

local P = {}

local function parse(src)
    local tokens = lexer.lex(src)
    local i = 1

    local function skipTrivia()
        while tokens[i] and (tokens[i].kind == "space" or tokens[i].kind == "comment") do
            i = i + 1
        end
    end

    local function tok()
        skipTrivia()
        return tokens[i]
    end

    local function at(kind, value)
        local t = tok()
        if not t then
            return false
        end
        if kind and t.kind ~= kind then
            return false
        end
        if value and t.value ~= value then
            return false
        end
        return true
    end

    local function loc()
        local t = tok() or tokens[#tokens]
        return (t.line or 0) .. ":" .. (t.col or 0)
    end

    local function fail(msg)
        error(msg .. " at " .. loc())
    end

    local function consume(kind, value)
        local t = tok()
        if not t or (kind and t.kind ~= kind) or (value and t.value ~= value) then
            fail("expected " .. (value or kind or "token"))
        end
        i = i + 1
        return t
    end

    local function try(kind, value)
        if at(kind, value) then
            local t = tok()
            i = i + 1
            return t
        end
        return nil
    end

    local parseBlock, parseExp, parseExplist, parsePrefix

    local function parseName()
        local t = consume("ident")
        return { tag = "name", value = t.value, line = t.line, col = t.col }
    end

    local function parseNamelist()
        local names = { parseName() }
        while try("punct", ",") do
            names[#names + 1] = parseName()
        end
        return names
    end

    local function parseAttName()
        local name = parseName()
        local attr
        if try("punct", "<") then
            attr = consume("ident").value
            consume("punct", ">")
        end
        name.attr = attr
        return name
    end

    local function parseAttNamelist()
        local names = { parseAttName() }
        while try("punct", ",") do
            names[#names + 1] = parseAttName()
        end
        return names
    end

    local function parseParlist()
        local names = {}
        local vararg = false
        if try("punct", "...") then
            return { vararg = true, names = names }
        end
        if at("ident") then
            names[#names + 1] = parseName()
            while try("punct", ",") do
                if try("punct", "...") then
                    vararg = true
                    break
                end
                names[#names + 1] = parseName()
            end
        end
        return { vararg = vararg, names = names }
    end

    local function parseField()
        if try("punct", "[") then
            local key = parseExp()
            consume("punct", "]")
            consume("punct", "=")
            return { tag = "indexfield", key = key, value = parseExp() }
        end
        if at("ident") then
            local save = i
            local name = parseName()
            if try("punct", "=") then
                return { tag = "namefield", name = name, value = parseExp() }
            end
            i = save
        end
        return { tag = "listfield", value = parseExp() }
    end

    local function parseTable()
        consume("punct", "{")
        local fields = {}
        if not at("punct", "}") then
            fields[#fields + 1] = parseField()
            while try("punct", ",") or try("punct", ";") do
                if at("punct", "}") then
                    break
                end
                fields[#fields + 1] = parseField()
            end
        end
        consume("punct", "}")
        return { tag = "table", fields = fields }
    end

    local function parseArgs()
        if at("punct", "(") then
            consume("punct", "(")
            local list = {}
            if not at("punct", ")") then
                list = parseExplist()
            end
            consume("punct", ")")
            return list
        end
        if at("punct", "{") then
            return { parseTable() }
        end
        if at("string") then
            local t = consume("string")
            return { { tag = "string", value = t.value } }
        end
        fail("expected arguments")
    end

    local function parseFuncbody()
        consume("punct", "(")
        local params = parseParlist()
        consume("punct", ")")
        local body = parseBlock()
        consume("keyword", "end")
        return { tag = "funcbody", params = params, body = body }
    end

    parsePrefix = function()
        local node
        if try("punct", "(") then
            node = parseExp()
            consume("punct", ")")
            node = { tag = "paren", exp = node }
        elseif at("ident") then
            node = parseName()
        else
            fail("expected prefix expression")
        end
        while true do
            if try("punct", ".") then
                node = { tag = "field", object = node, name = parseName() }
            elseif try("punct", "[") then
                local index = parseExp()
                consume("punct", "]")
                node = { tag = "index", object = node, index = index }
            elseif try("punct", ":") then
                local name = parseName()
                local args = parseArgs()
                node = { tag = "mcall", object = node, name = name, args = args }
            elseif at("punct", "(") or at("punct", "{") or at("string") then
                node = { tag = "call", callee = node, args = parseArgs() }
            else
                break
            end
        end
        return node
    end

    local function parsePrimary()
        if try("keyword", "nil") then
            return { tag = "nil" }
        end
        if try("keyword", "false") then
            return { tag = "boolean", value = false }
        end
        if try("keyword", "true") then
            return { tag = "boolean", value = true }
        end
        if at("number") then
            return { tag = "number", value = consume("number").value }
        end
        if at("string") then
            return { tag = "string", value = consume("string").value }
        end
        if try("punct", "...") then
            return { tag = "vararg" }
        end
        if try("keyword", "function") then
            return parseFuncbody()
        end
        if at("punct", "{") then
            return parseTable()
        end
        return parsePrefix()
    end

    local UNOPS = { ["not"] = 10, ["#"] = 10, ["-"] = 10, ["~"] = 10 }
    local BINOPS = {
        ["or"] = { 1, 1 },
        ["and"] = { 2, 2 },
        ["<"] = { 3, 3 }, [">"] = { 3, 3 }, ["<="] = { 3, 3 }, [">="] = { 3, 3 },
        ["~="] = { 3, 3 }, ["=="] = { 3, 3 },
        ["|"] = { 4, 4 },
        ["~"] = { 5, 5 },
        ["&"] = { 6, 6 },
        ["<<"] = { 7, 7 }, [">>"] = { 7, 7 },
        [".."] = { 8, 7 },
        ["+"] = { 9, 9 }, ["-"] = { 9, 9 },
        ["*"] = { 10, 10 }, ["/"] = { 10, 10 }, ["//"] = { 10, 10 }, ["%"] = { 10, 10 },
        ["^"] = { 12, 11 },
    }

    local function lbp()
        local t = tok()
        if not t then
            return 0
        end
        if t.kind == "keyword" and (t.value == "and" or t.value == "or") then
            return BINOPS[t.value][1]
        end
        if t.kind == "punct" and BINOPS[t.value] then
            return BINOPS[t.value][1]
        end
        return 0
    end

    local function parseUnop()
        skipTrivia()
        local t = tok()
        if t and ((t.kind == "keyword" and t.value == "not") or (t.kind == "punct" and UNOPS[t.value])) then
            i = i + 1
            return { tag = "unop", op = t.value, exp = parseExp(UNOPS[t.value]) }
        end
        return parsePrimary()
    end

    parseExp = function(rbp)
        rbp = rbp or 0
        local left = parseUnop()
        while lbp() > rbp do
            local t = tok()
            local op = t.value
            local info = BINOPS[op]
            i = i + 1
            local right = parseExp(info[2])
            left = { tag = "binop", op = op, left = left, right = right }
        end
        return left
    end

    parseExplist = function()
        local list = { parseExp() }
        while try("punct", ",") do
            list[#list + 1] = parseExp()
        end
        return list
    end

    local function parseFuncname()
        local name = parseName()
        local method = false
        while try("punct", ".") do
            name = { tag = "field", object = name, name = parseName() }
        end
        if try("punct", ":") then
            name = { tag = "field", object = name, name = parseName() }
            method = true
        end
        return name, method
    end

    local function parseStat()
        if try("punct", ";") then
            return { tag = "empty" }
        end
        if try("keyword", "break") then
            return { tag = "break" }
        end
        if try("keyword", "goto") then
            return { tag = "goto", name = parseName() }
        end
        if try("punct", "::") then
            local name = parseName()
            consume("punct", "::")
            return { tag = "label", name = name }
        end
        if try("keyword", "do") then
            local body = parseBlock()
            consume("keyword", "end")
            return { tag = "do", body = body }
        end
        if try("keyword", "while") then
            local cond = parseExp()
            consume("keyword", "do")
            local body = parseBlock()
            consume("keyword", "end")
            return { tag = "while", cond = cond, body = body }
        end
        if try("keyword", "repeat") then
            local body = parseBlock()
            consume("keyword", "until")
            return { tag = "repeat", body = body, cond = parseExp() }
        end
        if try("keyword", "if") then
            local clauses = {}
            local cond = parseExp()
            consume("keyword", "then")
            clauses[#clauses + 1] = { cond = cond, body = parseBlock() }
            while try("keyword", "elseif") do
                cond = parseExp()
                consume("keyword", "then")
                clauses[#clauses + 1] = { cond = cond, body = parseBlock() }
            end
            local els
            if try("keyword", "else") then
                els = parseBlock()
            end
            consume("keyword", "end")
            return { tag = "if", clauses = clauses, els = els }
        end
        if try("keyword", "for") then
            local name = parseName()
            if try("punct", "=") then
                local e1 = parseExp()
                consume("punct", ",")
                local e2 = parseExp()
                local e3
                if try("punct", ",") then
                    e3 = parseExp()
                end
                consume("keyword", "do")
                local body = parseBlock()
                consume("keyword", "end")
                return { tag = "fornum", name = name, from = e1, to = e2, step = e3, body = body }
            end
            local names = { name }
            while try("punct", ",") do
                names[#names + 1] = parseName()
            end
            consume("keyword", "in")
            local iters = parseExplist()
            consume("keyword", "do")
            local body = parseBlock()
            consume("keyword", "end")
            return { tag = "forin", names = names, explist = iters, body = body }
        end
        if try("keyword", "function") then
            local fname, method = parseFuncname()
            local body = parseFuncbody()
            body.method = method
            return { tag = "functionstat", name = fname, body = body }
        end
        if try("keyword", "local") then
            if try("keyword", "function") then
                local name = parseName()
                local body = parseFuncbody()
                return { tag = "localfunction", name = name, body = body }
            end
            local names = parseAttNamelist()
            local values
            if try("punct", "=") then
                values = parseExplist()
            end
            return { tag = "local", names = names, values = values }
        end
        if try("keyword", "return") then
            local list
            if not at("keyword", "end") and not at("keyword", "else") and not at("keyword", "elseif")
                and not at("keyword", "until") and not at("punct", ";") and not at("eof") then
                list = parseExplist()
            end
            try("punct", ";")
            return { tag = "return", explist = list }
        end
        local prefix = parsePrefix()
        if prefix.tag == "call" or prefix.tag == "mcall" then
            return { tag = "callstat", call = prefix }
        end
        local vars = { prefix }
        while try("punct", ",") do
            vars[#vars + 1] = parsePrefix()
        end
        consume("punct", "=")
        return { tag = "assign", vars = vars, values = parseExplist() }
    end

    parseBlock = function()
        local stats = {}
        while true do
            skipTrivia()
            if at("eof") or at("keyword", "end") or at("keyword", "else")
                or at("keyword", "elseif") or at("keyword", "until") then
                break
            end
            local st = parseStat()
            stats[#stats + 1] = st
            if st.tag == "return" then
                break
            end
        end
        return { tag = "block", stats = stats }
    end

    local chunk = parseBlock()
    skipTrivia()
    if not at("eof") then
        fail("expected end of file")
    end
    return chunk
end

function P.parse(src)
    return parse(src)
end

return P
