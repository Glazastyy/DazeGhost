#include <lua.hpp>

#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

namespace fs = std::filesystem;

static constexpr char magic[] = "DGNATIVE54";
static constexpr std::size_t magic_size = sizeof(magic) - 1;

static bool read_u64_le(std::istream& input, std::uint64_t& value) {
    char bytes[sizeof(value)];
    input.read(bytes, sizeof(bytes));
    if (!input) return false;
    value = 0;
    for (std::size_t index = 0; index < sizeof(value); ++index) {
        value |= static_cast<std::uint64_t>(static_cast<unsigned char>(bytes[index])) << (index * 8);
    }
    return true;
}

static bool read_payload(const fs::path& executable, std::string& payload) {
    std::ifstream file(executable, std::ios::binary);
    if (!file) return false;
    file.seekg(0, std::ios::end);
    const std::streamoff size = file.tellg();
    if (size < static_cast<std::streamoff>(magic_size + sizeof(std::uint64_t))) return false;
    file.seekg(size - static_cast<std::streamoff>(magic_size), std::ios::beg);
    std::string found_magic(magic_size, '\0');
    file.read(found_magic.data(), static_cast<std::streamsize>(magic_size));
    if (!file || found_magic != magic) return false;
    file.seekg(size - static_cast<std::streamoff>(magic_size + sizeof(std::uint64_t)), std::ios::beg);
    std::uint64_t payload_size = 0;
    if (!read_u64_le(file, payload_size) || payload_size > static_cast<std::uint64_t>(size - magic_size - sizeof(payload_size))) return false;
    file.seekg(size - static_cast<std::streamoff>(magic_size + sizeof(payload_size)) - static_cast<std::streamoff>(payload_size), std::ios::beg);
    payload.resize(static_cast<std::size_t>(payload_size));
    file.read(payload.data(), static_cast<std::streamsize>(payload.size()));
    return static_cast<bool>(file);
}

static fs::path executable_path(const char* argument) {
    std::error_code error;
    return fs::absolute(argument, error);
}

int main(int argc, char** argv) {
    const fs::path executable = executable_path(argc > 0 ? argv[0] : "dazeghost-loader");
    std::string payload;
    if (!read_payload(executable, payload)) {
        std::cerr << "invalid DazeGhost native loader payload\n";
        return 1;
    }
    std::cerr << "[dazeghost] Native loader starting.\n";
    lua_State* state = luaL_newstate();
    if (!state) {
        std::cerr << "cannot initialize embedded Lua 5.4 runtime\n";
        return 1;
    }
    luaL_openlibs(state);
    if (luaL_loadbufferx(state, payload.data(), payload.size(), "=dazeghost-native-payload", "t") != LUA_OK) {
        const char* message = lua_tostring(state, -1);
        std::cerr << (message ? message : "cannot load native payload") << '\n';
        lua_close(state);
        return 1;
    }
    if (lua_pcall(state, 0, LUA_MULTRET, 0) != LUA_OK) {
        const char* message = lua_tostring(state, -1);
        std::cerr << (message ? message : "native payload execution failed") << '\n';
        lua_close(state);
        return 1;
    }
    lua_close(state);
    return 0;
}
