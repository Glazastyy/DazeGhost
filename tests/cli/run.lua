arg = { "--input", "tests/fixtures/script.lua", "--decoy", "tests/fixtures/caos.lua", "--output", "tests/cli/protegido.lua", "--rounds", "3", "--density", "60", "--compress" }
dofile("gerar.lua")
assert(dofile("tests/cli/protegido.lua") == 42)
os.remove("tests/cli/protegido.lua")
