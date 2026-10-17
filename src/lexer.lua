local M = {}

local KEYWORDS = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
    ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
    ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
    ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
    ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
    ["until"] = true, ["while"] = true,
}

local OPS = {
    "...", "..", "==", "~=", "<=", ">=", "<<", ">>", "//", "::",
}

local function peek(src, i, n)
    return src:sub(i, i + (n or 1) - 1)
end

local function isIdentStart(c)
    return c:match("[%a_]") ~= nil
end

local function isIdent(c)
    return c:match("[%w_]") ~= nil
end

local function isDigit(c)
    return c:match("%d") ~= nil
end

local function readLongBracket(src, i)
    local eqs = src:match("^%[(=*)%[", i)
    if not eqs then
        return nil
    end
    local close = "]" .. eqs .. "]"
    local start = i + 2 + #eqs
    local j = src:find(close, start, true)
    if not j then
        return nil, "unfinished long bracket"
    end
    return src:sub(i, j + #close - 1), j + #close
end

local function readString(src, i)
    local q = peek(src, i)
    local j = i + 1
    local n = #src
    while j <= n do
        local c = peek(src, j)
        if c == "\\" then
            j = j + 2
        elseif c == q then
            return src:sub(i, j), j + 1
        elseif c == "\n" then
            return nil, "unfinished string"
        else
            j = j + 1
        end
    end
    return nil, "unfinished string"
end

local function readNumber(src, i)
    local s = src:sub(i)
    local num = s:match("^0[xX][%da-fA-F]*[pP][%+%-]?%d+")
        or s:match("^0[xX][%da-fA-F]+%.[%da-fA-F]*[pP][%+%-]?%d+")
        or s:match("^0[xX]%.[%da-fA-F]+[pP][%+%-]?%d+")
        or s:match("^0[xX][%da-fA-F]+%.[%da-fA-F]*")
        or s:match("^0[xX]%.[%da-fA-F]+")
        or s:match("^0[xX][%da-fA-F]+")
        or s:match("^%d+%.%d*[eE][%+%-]?%d+")
        or s:match("^%d+[eE][%+%-]?%d+")
        or s:match("^%.%d+[eE][%+%-]?%d+")
        or s:match("^%d+%.%d*")
        or s:match("^%.%d+")
        or s:match("^%d+")
    if not num or num == "0x" or num == "0X" then
        return nil
    end
    return num, i + #num
end

local function readOp(src, i)
    for _, op in ipairs(OPS) do
        if peek(src, i, #op) == op then
            return op, i + #op
        end
    end
    local c = peek(src, i)
    if c ~= "" and c:match("[%+%-%*%/%%%^#%=%<%>%(%)%{%}%[%]%,%;%:%&%.~|]") then
        return c, i + 1
    end
    return nil
end

function M.lex(src)
    local tokens = {}
    local i = 1
    local n = #src
    local line, col = 1, 1

    local function adv(to)
        while i < to do
            if peek(src, i) == "\n" then
                line = line + 1
                col = 1
            else
                col = col + 1
            end
            i = i + 1
        end
    end

    local function emit(kind, value, sl, sc)
        tokens[#tokens + 1] = { kind = kind, value = value, line = sl, col = sc }
    end

    if peek(src, 1, 2) == "#!" then
        local j = src:find("\n", 1, true) or (n + 1)
        emit("comment", src:sub(1, j - 1), 1, 1)
        adv(j)
    end

    while i <= n do
        local sl, sc = line, col
        local c = peek(src, i)
        if c:match("%s") then
            local j = i
            while j <= n and peek(src, j):match("%s") do
                j = j + 1
            end
            emit("space", src:sub(i, j - 1), sl, sc)
            adv(j)
        elseif src:match("^%-%-%[=*%[", i) then
            local body, ni = readLongBracket(src, i + 2)
            if not body then
                error("unfinished long comment at " .. sl .. ":" .. sc)
            end
            emit("comment", "--" .. body, sl, sc)
            adv(ni)
        elseif peek(src, i, 2) == "--" then
            local j = src:find("\n", i, true) or (n + 1)
            emit("comment", src:sub(i, j - 1), sl, sc)
            adv(j)
        elseif c == "'" or c == '"' then
            local body, ni = readString(src, i)
            if not body then
                error("unfinished string at " .. sl .. ":" .. sc)
            end
            emit("string", body, sl, sc)
            adv(ni)
        elseif c == "[" and src:match("^%[=*%[", i) then
            local body, ni = readLongBracket(src, i)
            if not body then
                error("unfinished long string at " .. sl .. ":" .. sc)
            end
            emit("string", body, sl, sc)
            adv(ni)
        elseif isDigit(c) or (c == "." and isDigit(peek(src, i + 1))) then
            local body, ni = readNumber(src, i)
            if not body then
                error("bad number at " .. sl .. ":" .. sc)
            end
            emit("number", body, sl, sc)
            adv(ni)
        elseif isIdentStart(c) then
            local j = i
            while j <= n and isIdent(peek(src, j)) do
                j = j + 1
            end
            local word = src:sub(i, j - 1)
            if KEYWORDS[word] then
                emit("keyword", word, sl, sc)
            else
                emit("ident", word, sl, sc)
            end
            adv(j)
        else
            local body, ni = readOp(src, i)
            if not body then
                error("unexpected " .. c .. " at " .. sl .. ":" .. sc)
            end
            emit("punct", body, sl, sc)
            adv(ni)
        end
    end
    emit("eof", "", line, col)
    return tokens
end

M.keywords = KEYWORDS
return M
