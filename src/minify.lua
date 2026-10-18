local parser = require("src.parser")
local emit = require("src.emit")

local M = {}

function M.minify(src)
    if type(src) ~= "string" then
        error("source must be a string", 2)
    end
    local output = emit.emit(parser.parse(src))
    local compiled, err = load(output, "=minified", "t")
    if not compiled then
        error("minified code is invalid: " .. tostring(err), 2)
    end
    return output
end

return M
