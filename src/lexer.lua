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
    local quote = src:sub(i, i)
    local j = i + 1
    local n = #src
    while j <= n do
        local c = src:sub(j, j)
        if c == quote then
            return src:sub(i, j), j + 1
        end
        if c == "\\" then
            local nextc = src:sub(j + 1, j + 1)
            if nextc == "" then
                return nil, "unfinished string"
            end
            if nextc == "z" then
                j = j + 2
                while j <= n and src:sub(j, j):match("%s") do
                    j = j + 1
                end
            elseif nextc == "\r" and src:sub(j + 2, j + 2) == "\n" then
                j = j + 3
            elseif nextc == "\n" and src:sub(j + 2, j + 2) == "\r" then
                j = j + 3
            else
                j = j + 2
            end
        elseif c == "\n" or c == "\r" then
            return nil, "unfinished string"
        else
            j = j + 1
        end
    end
    return nil, "unfinished string"
end

local function readNumber(src, i)
    local n = #src
    local j = i
    local hexadecimal = src:sub(i, i + 1):lower() == "0x"
    if hexadecimal then
        j = j + 2
    end
    local pattern = hexadecimal and "[%da-fA-F]" or "%d"
    local digits = 0
    while j <= n and src:sub(j, j):match(pattern) do
        j = j + 1
        digits = digits + 1
    end
    if src:sub(j, j) == "." and src:sub(j + 1, j + 1) ~= "." then
        j = j + 1
        while j <= n and src:sub(j, j):match(pattern) do
            j = j + 1
            digits = digits + 1
        end
    end
    if digits == 0 then
        return nil
    end
    local marker = src:sub(j, j)
    if (hexadecimal and (marker == "p" or marker == "P")) or (not hexadecimal and (marker == "e" or marker == "E")) then
        j = j + 1
        local sign = src:sub(j, j)
        if sign == "+" or sign == "-" then
            j = j + 1
        end
        local start = j
        while j <= n and src:sub(j, j):match("%d") do
            j = j + 1
        end
        if j == start then
            return nil
        end
    end
    return src:sub(i, j - 1), j
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
    local i = src:sub(1, 3) == "\239\187\191" and 4 or 1
    local n = #src
    local line, col = 1, 1

    local function adv(to)
        while i < to do
            local c = peek(src, i)
            if c == "\r" or c == "\n" then
                line = line + 1
                col = 1
                if c == "\r" and peek(src, i + 1) == "\n" and i + 1 < to then
                    i = i + 1
                end
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
