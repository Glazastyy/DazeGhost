local parser = require("src.parser")
local emit = require("src.emit")

local M = {}

function M.minify(src)
    return emit.emit(parser.parse(src))
end

return M
