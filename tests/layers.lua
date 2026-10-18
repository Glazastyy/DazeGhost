local crypt = require("src.crypt")

local source = "return 17 * 3"
local outputs = {}
for variant = 1, 5 do
    local protected = crypt.seal(source, {
        mode = "text",
        seed = 321,
        cipher_variant = variant,
        runtime = ({ "linear", "state", "table", "linear", "state" })[variant]
    })
    local chunk, err = load(protected, "=layer-" .. variant, "t")
    assert(chunk, err)
    assert(chunk() == 51)
    assert(not outputs[protected])
    outputs[protected] = true
end

print("passed: distinct layer protection profiles")
