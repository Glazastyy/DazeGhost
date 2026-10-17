#!/usr/bin/env lua

local function addPath()
    local here = arg[0]:match("^(.*[/\\])") or "./"
    package.path = here .. "?.lua;" .. here .. "?/init.lua;" .. package.path
end
addPath()

local minify = require("src.minify")
local obfuscate = require("src.obfuscate")

local function usage()
    io.stderr:write("usage: dazeghost [--minify|--obfuscate] [--anti-ia] [-o out.lua] file.lua\n")
    os.exit(2)
end

local mode = "obfuscate"
local anti_ia = false
local input, output
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "-h" or a == "--help" then
        usage()
    elseif a == "--minify" then
        mode = "minify"
    elseif a == "--obfuscate" then
        mode = "obfuscate"
    elseif a == "--anti-ia" then
        anti_ia = true
    elseif a == "-o" then
        i = i + 1
        output = arg[i]
        if not output then
            usage()
        end
    elseif a:sub(1, 1) == "-" then
        usage()
    else
        if input then
            usage()
        end
        input = a
    end
    i = i + 1
end

if not input then
    usage()
end

local f, err = io.open(input, "rb")
if not f then
    io.stderr:write(err .. "\n")
    os.exit(1)
end
local src = f:read("*a")
f:close()

local out
if mode == "minify" then
    out = minify.minify(src)
else
    out = obfuscate.obfuscate(src, { anti_ia = anti_ia })
end

if output then
    local w, werr = io.open(output, "wb")
    if not w then
        io.stderr:write(werr .. "\n")
        os.exit(1)
    end
    w:write(out)
    if out:sub(-1) ~= "\n" then
        w:write("\n")
    end
    w:close()
else
    io.write(out)
    if out:sub(-1) ~= "\n" then
        io.write("\n")
    end
end
