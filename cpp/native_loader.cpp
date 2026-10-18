#include <lua.hpp>
#include <openssl/evp.h>

#include <array>
#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

namespace fs = std::filesystem;

static constexpr char magic[] = "DGNATIVE54";
static constexpr std::size_t magic_size = sizeof(magic) - 1;
static constexpr char binding_magic[] = "DGVMSEPARATE54";
static constexpr std::size_t binding_magic_size = sizeof(binding_magic) - 1;
static constexpr std::size_t digest_size = 32;

struct Binding {
    std::string filename;
    std::array<unsigned char, digest_size> digest{};
};

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

static bool read_bytes(const fs::path& path, std::string& content) {
    std::ifstream file(path, std::ios::binary);
    if (!file) return false;
    file.seekg(0, std::ios::end);
    const std::streamoff size = file.tellg();
    if (size < 0) return false;
    file.seekg(0, std::ios::beg);
    content.resize(static_cast<std::size_t>(size));
    file.read(content.data(), static_cast<std::streamsize>(content.size()));
    return static_cast<bool>(file) || content.empty();
}

static bool sha256(const std::string& content, std::array<unsigned char, digest_size>& digest) {
    EVP_MD_CTX* context = EVP_MD_CTX_new();
    if (!context) return false;
    unsigned int length = 0;
    const bool initialized = EVP_DigestInit_ex(context, EVP_sha256(), nullptr) == 1;
    const bool updated = initialized && EVP_DigestUpdate(context, content.data(), content.size()) == 1;
    const bool finalized = updated && EVP_DigestFinal_ex(context, digest.data(), &length) == 1;
    EVP_MD_CTX_free(context);
    return finalized && length == digest_size;
}

static bool read_binding(const fs::path& executable, Binding& binding) {
    std::string file;
    if (!read_bytes(executable, file)) return false;
    const std::size_t minimum = binding_magic_size + digest_size + sizeof(std::uint64_t) + 1;
    if (file.size() < minimum) return false;
    if (file.compare(file.size() - binding_magic_size, binding_magic_size, binding_magic) != 0) return false;
    const std::size_t digest_offset = file.size() - binding_magic_size - digest_size;
    std::copy_n(reinterpret_cast<const unsigned char*>(file.data() + digest_offset), digest_size, binding.digest.begin());
    const std::size_t size_offset = digest_offset - sizeof(std::uint64_t);
    std::uint64_t filename_size = 0;
    for (std::size_t index = 0; index < sizeof(filename_size); ++index) {
        filename_size |= static_cast<std::uint64_t>(static_cast<unsigned char>(file[size_offset + index])) << (index * 8);
    }
    if (filename_size == 0 || filename_size > size_offset) return false;
    const std::size_t filename_offset = size_offset - static_cast<std::size_t>(filename_size);
    binding.filename.assign(file.data() + filename_offset, static_cast<std::size_t>(filename_size));
    const fs::path candidate(binding.filename);
    if (candidate.empty() || candidate.has_parent_path() || candidate.filename() != candidate) return false;
    return true;
}

static fs::path executable_path(const char* argument) {
    std::error_code error;
    return fs::absolute(argument, error);
}

static int native_load(lua_State* state) {
    size_t length = 0;
    const char* data = luaL_checklstring(state, 1, &length);
    const char* name = luaL_optstring(state, 2, "=dazeghost-native-payload");
    const char* mode = luaL_optstring(state, 3, "bt");
    if (luaL_loadbufferx(state, data, length, name, mode) == LUA_OK) {
        return 1;
    }
    lua_pushnil(state);
    lua_insert(state, -2);
    return 2;
}

int main(int argc, char** argv) {
    const fs::path executable = executable_path(argc > 0 ? argv[0] : "dazeghost-loader");
    std::string payload;
    Binding binding;
    std::string executable_bytes;
    const bool has_binding = read_bytes(executable, executable_bytes)
        && executable_bytes.size() >= binding_magic_size
        && executable_bytes.compare(executable_bytes.size() - binding_magic_size, binding_magic_size, binding_magic) == 0;
    if (has_binding) {
        if (argc != 1 || !read_binding(executable, binding)) {
            std::cerr << "invalid DazeGhost separated VM binding\n";
            return 1;
        }
        const fs::path artifact = executable.parent_path() / binding.filename;
        if (!read_bytes(artifact, payload)) {
            std::cerr << "bound DazeGhost artifact is unavailable\n";
            return 1;
        }
        std::array<unsigned char, digest_size> actual{};
        if (!sha256(payload, actual) || actual != binding.digest) {
            std::cerr << "bound DazeGhost artifact failed integrity validation\n";
            return 1;
        }
    } else if (!read_payload(executable, payload)) {
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
    lua_pushcfunction(state, native_load);
    lua_setglobal(state, "dazeghost_load");
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
