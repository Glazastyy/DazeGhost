local obfuscate = require("src.obfuscate")
local input = "local x=4;return x*x"
for round=1,3 do
    local result = obfuscate.obfuscate(input, { anti_ia=true, decoy_src="tests/fixtures/caos.lua", mode="text", rounds=round, seed=72, decoy_density=45 })
    assert(assert(load(result))() == 16)
    print(round, #result)
end
