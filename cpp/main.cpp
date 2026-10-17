#include <lua.hpp>

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

static void usage() {
    std::cerr << "usage: dazeghost [--minify|--obfuscate] [--anti-ia] [-o out.lua] file.lua\n";
}

static std::string slurp(const fs::path& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        return {};
    }
    std::ostringstream ss;
    ss << in.rdbuf();
    return ss.str();
}

static fs::path find_root(const fs::path& argv0) {
    std::vector<fs::path> candidates;
    std::error_code ec;
    if (const char* env = std::getenv("DAZEGHOST_ROOT")) {
        candidates.emplace_back(env);
    }
    fs::path exe = fs::absolute(argv0, ec);
    if (!ec) {
        candidates.push_back(exe.parent_path());
        candidates.push_back(exe.parent_path().parent_path());
    }
    candidates.push_back(fs::current_path());
    for (const auto& c : candidates) {
        if (fs::exists(c / "src" / "parser.lua")) {
            return c;
        }
    }
    return fs::current_path();
}

int main(int argc, char** argv) {
    std::string mode = "obfuscate";
    bool anti_ia = false;
    std::string input;
    std::string output;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "-h" || a == "--help") {
            usage();
            return 0;
        }
        if (a == "--minify") {
            mode = "minify";
            continue;
        }
        if (a == "--obfuscate") {
            mode = "obfuscate";
            continue;
        }
        if (a == "--anti-ia") {
            anti_ia = true;
            continue;
        }
        if (a == "-o") {
            if (i + 1 >= argc) {
                usage();
                return 2;
            }
            output = argv[++i];
            continue;
        }
        if (!a.empty() && a[0] == '-') {
            usage();
            return 2;
        }
        if (!input.empty()) {
            usage();
            return 2;
        }
        input = a;
    }
    if (input.empty()) {
        usage();
        return 2;
    }

    const std::string src = slurp(input);
    if (src.empty() && !fs::exists(input)) {
        std::cerr << "cannot read " << input << "\n";
        return 1;
    }

    lua_State* L = luaL_newstate();
    if (!L) {
        std::cerr << "lua state failed\n";
        return 1;
    }
    luaL_openlibs(L);

    const fs::path root = find_root(argv[0]);
    std::string setpath = "package.path = [[" + root.generic_string()
        + "/?.lua;" + root.generic_string() + "/?/init.lua;]] .. package.path";
    if (luaL_dostring(L, setpath.c_str()) != LUA_OK) {
        std::cerr << lua_tostring(L, -1) << "\n";
        lua_close(L);
        return 1;
    }

    const char* mod = (mode == "minify") ? "src.minify" : "src.obfuscate";
    lua_getglobal(L, "require");
    lua_pushstring(L, mod);
    if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
        std::cerr << lua_tostring(L, -1) << "\n";
        lua_close(L);
        return 1;
    }
    lua_getfield(L, -1, mode.c_str());
    if (!lua_isfunction(L, -1)) {
        std::cerr << "missing " << mode << "\n";
        lua_close(L);
        return 1;
    }
    lua_pushlstring(L, src.data(), src.size());
    int nargs = 1;
    if (mode == "obfuscate") {
        lua_newtable(L);
        lua_pushboolean(L, anti_ia ? 1 : 0);
        lua_setfield(L, -2, "anti_ia");
        nargs = 2;
    }
    if (lua_pcall(L, nargs, 1, 0) != LUA_OK) {
        std::cerr << lua_tostring(L, -1) << "\n";
        lua_close(L);
        return 1;
    }
    size_t n = 0;
    const char* out = lua_tolstring(L, -1, &n);
    if (!out) {
        std::cerr << "empty result\n";
        lua_close(L);
        return 1;
    }
    std::string result(out, n);
    if (result.empty() || result.back() != '\n') {
        result.push_back('\n');
    }
    lua_close(L);

    if (output.empty()) {
        std::cout << result;
        return 0;
    }
    std::ofstream w(output, std::ios::binary);
    if (!w) {
        std::cerr << "cannot write " << output << "\n";
        return 1;
    }
    w << result;
    return 0;
}
