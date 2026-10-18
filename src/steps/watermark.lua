local M = {}

function M.apply(ast, context)
    local watermark = context.options.watermark
    if watermark == nil then
        return
    end
    if type(watermark) ~= "string" or watermark == "" then
        error("watermark must be a nonempty string", 3)
    end
    local name = context.freshName()
    local value = string.format("%q", watermark)
    table.insert(ast.stats, 1, {
        tag = "local",
        names = {{ tag = "name", value = name, fixed = true }},
        values = {{ tag = "string", value = value }}
    })
    table.insert(ast.stats, 2, {
        tag = "if",
        clauses = {{
            cond = {
                tag = "binop",
                op = "~=",
                left = { tag = "name", value = name, fixed = true },
                right = { tag = "string", value = value }
            },
            body = {
                tag = "block",
                stats = {{
                    tag = "return",
                    explist = nil
                }}
            }
        }}
    })
end

return M
