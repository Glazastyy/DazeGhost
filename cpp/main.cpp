#include <lua.hpp>

#include <charconv>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <sstream>
#include <string>
#include <system_error>
#include <vector>

namespace fs = std::filesystem;

struct Options {
    std::string mode = "obfuscate";
    std::string payload_mode = "bytecode";
    std::string runtime = "auto";
    std::string input;
    std::string decoy = "caos.lua";
    std::string output;
    std::uint32_t rounds = 1;
    std::uint32_t density = 100;
    std::uint32_t seed = 0;
    bool has_seed = false;
    std::uint32_t min_chunk_size = 24;
    std::uint32_t max_chunk_size = 80;
    bool has_min_chunk_size = false;
    bool has_max_chunk_size = false;
    std::uint32_t noise_density = 25;
    std::uint64_t max_output_bytes = 12ULL * 1024ULL * 1024ULL;
    std::uint64_t max_intermediate_bytes = 0;
    bool mix_original = true;
    bool flatten = true;
    bool encode_strings = true;
    bool split_strings = true;
    bool numbers_to_expressions = true;
    bool constant_array = true;
    bool proxify_locals = true;
    bool anti_tamper = false;
    bool has_watermark = false;
    std::string watermark;
    bool compress = false;
    bool native_loader = false;
    bool has_secret = false;
    std::string secret;
    std::string secret_file = "dazeghost.secret.txt";
};

struct StageContext {
    fs::path prefix;
};

static constexpr char native_magic[] = "DGNATIVE54";
static constexpr std::size_t native_magic_size = sizeof(native_magic) - 1;

static int stage_writer(lua_State* state) {
    auto* context = static_cast<StageContext*>(lua_touserdata(state, lua_upvalueindex(1)));
    if (!context) return luaL_error(state, "stage context is unavailable");
    size_t length = 0;
    const char* data = luaL_checklstring(state, 1, &length);
    const lua_Integer round = luaL_checkinteger(state, 2);
    const fs::path path = context->prefix.string() + "." + std::to_string(round);
    std::ofstream stage(path, std::ios::binary | std::ios::trunc);
    if (!stage) return luaL_error(state, "cannot create stage file");
    stage.write(data, static_cast<std::streamsize>(length));
    stage.close();
    if (!stage) return luaL_error(state, "cannot write stage file");
    std::ifstream input(path, std::ios::binary);
    if (!input) return luaL_error(state, "cannot reopen stage file");
    std::ostringstream content;
    content << input.rdbuf();
    input.close();
    std::error_code error;
    fs::remove(path, error);
    const std::string result = content.str();
    lua_pushlstring(state, result.data(), result.size());
    return 1;
}

static void usage(std::ostream& out) {
    out << "usage: dazeghost [options] file.lua\n"
        << "  --minify | --obfuscate\n"
        << "  --anti-ia\n"
        << "  -i, --input FILE\n"
        << "  -d, --decoy FILE\n"
        << "  -o, --output FILE\n"
        << "  -r, --rounds N\n"
        << "  --density N\n"
        << "  --mode bytecode|text\n"
        << "  --runtime auto|linear|state|table\n"
        << "  --compress\n"
        << "  --native-loader\n"
        << "  --anti-tamper\n"
        << "  --watermark TEXT\n"
        << "  --no-constant-array --no-numbers-to-expressions --no-split-strings\n"
        << "  --no-proxify-locals\n"
        << "  --secret [VALUE]\n"
        << "  --secret-file FILE\n"
        << "  --seed N\n"
        << "  --min-chunk-size N --max-chunk-size N\n"
        << "  --noise-density N\n"
        << "  --max-output-bytes N --max-intermediate-bytes N\n"
        << "  --no-mix-original --no-flatten --no-encode-strings\n";
}

static void status(const std::string& message) {
    std::cerr << "[dazeghost] " << message << '\n';
}

static std::string generate_secret() {
    std::random_device source;
    std::ostringstream value;
    value << std::hex << std::setfill('0');
    for (int index = 0; index < 32; ++index) {
        value << std::setw(2) << (source() & 0xFFU);
    }
    return value.str();
}

static bool save_secret(const fs::path& path, const std::string& secret) {
    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    if (!file) return false;
    file << secret << '\n';
    file.close();
    if (!file) return false;
    std::error_code error;
    fs::permissions(path, fs::perms::owner_read | fs::perms::owner_write, fs::perm_options::replace, error);
    return !error;
}

static bool parse_unsigned(const std::string& text, std::uint64_t& value) {
    if (text.empty() || text.front() == '-') return false;
    const char* first = text.data();
    const char* last = first + text.size();
    const auto result = std::from_chars(first, last, value);
    return result.ec == std::errc{} && result.ptr == last;
}

static bool next_value(int& index, int argc, char** argv, std::string& value) {
    if (index + 1 >= argc) return false;
    value = argv[++index];
    return !value.empty();
}

static bool assign_unsigned(const std::string& text, std::uint64_t maximum, std::uint64_t& destination) {
    std::uint64_t value = 0;
    if (!parse_unsigned(text, value) || value > maximum) return false;
    destination = value;
    return true;
}

static bool parse_arguments(int argc, char** argv, Options& options, bool& anti_ia, bool& show_help) {
    for (int index = 1; index < argc; ++index) {
        const std::string argument = argv[index];
        if (argument == "-h" || argument == "--help") {
            usage(std::cout);
            show_help = true;
            return false;
        }
        if (argument == "--minify" || argument == "--obfuscate") {
            options.mode = argument == "--minify" ? "minify" : "obfuscate";
            continue;
        }
        if (argument == "--anti-ia") {
            anti_ia = true;
            continue;
        }
        if (argument == "--no-mix-original") {
            options.mix_original = false;
            continue;
        }
        if (argument == "--no-flatten") {
            options.flatten = false;
            continue;
        }
        if (argument == "--no-encode-strings") {
            options.encode_strings = false;
            continue;
        }
        if (argument == "--no-constant-array") {
            options.constant_array = false;
            continue;
        }
        if (argument == "--no-numbers-to-expressions") {
            options.numbers_to_expressions = false;
            continue;
        }
        if (argument == "--no-split-strings") {
            options.split_strings = false;
            continue;
        }
        if (argument == "--no-proxify-locals") {
            options.proxify_locals = false;
            continue;
        }
        if (argument == "--anti-tamper") {
            options.anti_tamper = true;
            continue;
        }
        if (argument == "--compress") {
            options.compress = true;
            continue;
        }
        if (argument == "--native-loader") {
            options.native_loader = true;
            continue;
        }
        std::string value;
        if (argument == "--secret") {
            options.has_secret = true;
            if (index + 1 < argc && argv[index + 1][0] != '-') options.secret = argv[++index];
            continue;
        }
        if (argument.rfind("--secret=", 0) == 0) {
            options.has_secret = true;
            options.secret = argument.substr(9);
            if (options.secret.empty()) return false;
            continue;
        }
        if (argument == "--secret-file") {
            if (!next_value(index, argc, argv, value)) return false;
            options.secret_file = value;
            continue;
        }
        if (argument == "--watermark") {
            if (!next_value(index, argc, argv, value)) return false;
            options.watermark = value;
            options.has_watermark = true;
            continue;
        }
        if (argument.rfind("--watermark=", 0) == 0) {
            options.watermark = argument.substr(12);
            if (options.watermark.empty()) return false;
            options.has_watermark = true;
            continue;
        }
        if (argument == "-i" || argument == "--input") {
            if (!next_value(index, argc, argv, value)) return false;
            options.input = value;
            continue;
        }
        if (argument == "-d" || argument == "--decoy") {
            if (!next_value(index, argc, argv, value)) return false;
            options.decoy = value;
            continue;
        }
        if (argument == "-o" || argument == "--output") {
            if (!next_value(index, argc, argv, value)) return false;
            options.output = value;
            continue;
        }
        if (argument == "-r" || argument == "--rounds") {
            std::uint64_t parsed = 0;
            if (!next_value(index, argc, argv, value) || !assign_unsigned(value, 5, parsed) || parsed < 1) return false;
            options.rounds = static_cast<std::uint32_t>(parsed);
            continue;
        }
        if (argument == "--density") {
            std::uint64_t parsed = 0;
            if (!next_value(index, argc, argv, value) || !assign_unsigned(value, 100, parsed) || parsed < 1) return false;
            options.density = static_cast<std::uint32_t>(parsed);
            continue;
        }
        if (argument == "--seed") {
            std::uint64_t parsed = 0;
            if (!next_value(index, argc, argv, value) || !assign_unsigned(value, 0xFFFFFFFFULL, parsed)) return false;
            options.seed = static_cast<std::uint32_t>(parsed);
            options.has_seed = true;
            continue;
        }
        if (argument == "--min-chunk-size" || argument == "--max-chunk-size") {
            std::uint64_t parsed = 0;
            if (!next_value(index, argc, argv, value) || !assign_unsigned(value, 4096, parsed) || parsed < 1) return false;
            if (argument == "--min-chunk-size") {
                options.min_chunk_size = static_cast<std::uint32_t>(parsed);
                options.has_min_chunk_size = true;
            } else {
                options.max_chunk_size = static_cast<std::uint32_t>(parsed);
                options.has_max_chunk_size = true;
            }
            continue;
        }
        if (argument == "--noise-density") {
            std::uint64_t parsed = 0;
            if (!next_value(index, argc, argv, value) || !assign_unsigned(value, 100, parsed)) return false;
            options.noise_density = static_cast<std::uint32_t>(parsed);
            continue;
        }
        if (argument == "--max-output-bytes" || argument == "--max-intermediate-bytes") {
            std::uint64_t parsed = 0;
            if (!next_value(index, argc, argv, value) || !assign_unsigned(value, 0x7FFFFFFFFFFFFFFFULL, parsed) || parsed < 1024) return false;
            if (argument == "--max-output-bytes") options.max_output_bytes = parsed;
            else options.max_intermediate_bytes = parsed;
            continue;
        }
        if (argument == "--mode") {
            if (!next_value(index, argc, argv, value) || (value != "bytecode" && value != "text")) return false;
            options.payload_mode = value;
            continue;
        }
        if (argument == "--runtime") {
            if (!next_value(index, argc, argv, value) || (value != "auto" && value != "linear" && value != "state" && value != "table")) return false;
            options.runtime = value;
            continue;
        }
        if (!argument.empty() && argument.front() == '-') return false;
        if (!options.input.empty()) return false;
        options.input = argument;
    }
    return !options.input.empty();
}

static std::string slurp(const fs::path& path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) return {};
    std::ostringstream content;
    content << input.rdbuf();
    return content.str();
}

static void write_u64_le(std::ostream& output, std::uint64_t value) {
    char bytes[sizeof(value)];
    for (std::size_t index = 0; index < sizeof(value); ++index) {
        bytes[index] = static_cast<char>((value >> (index * 8)) & 0xFFU);
    }
    output.write(bytes, sizeof(bytes));
}

static bool append_native_payload(const fs::path& loader, const fs::path& output, const std::string& payload) {
    const std::string loader_bytes = slurp(loader);
    if (loader_bytes.empty()) return false;
    std::ofstream file(output, std::ios::binary | std::ios::trunc);
    if (!file) return false;
    file.write(loader_bytes.data(), static_cast<std::streamsize>(loader_bytes.size()));
    file.write(payload.data(), static_cast<std::streamsize>(payload.size()));
    write_u64_le(file, static_cast<std::uint64_t>(payload.size()));
    file.write(native_magic, static_cast<std::streamsize>(native_magic_size));
    file.close();
    if (!file) return false;
    std::error_code error;
    fs::permissions(output,
        fs::perms::owner_read | fs::perms::owner_write | fs::perms::owner_exec |
        fs::perms::group_read | fs::perms::group_exec |
        fs::perms::others_read | fs::perms::others_exec,
        fs::perm_options::replace,
        error);
    return !error;
}

static fs::path find_root(const fs::path& argv0) {
    std::vector<fs::path> candidates;
    std::error_code error;
    if (const char* environment = std::getenv("DAZEGHOST_ROOT")) candidates.emplace_back(environment);
    const fs::path executable = fs::absolute(argv0, error);
    if (!error) {
        candidates.push_back(executable.parent_path());
        candidates.push_back(executable.parent_path().parent_path());
    }
    candidates.push_back(fs::current_path());
    for (const auto& candidate : candidates) {
        if (fs::exists(candidate / "src" / "parser.lua")) return candidate;
    }
    return fs::current_path();
}

static bool configure_package_path(lua_State* state, const fs::path& root) {
    lua_getglobal(state, "package");
    if (!lua_istable(state, -1)) {
        lua_pop(state, 1);
        return false;
    }
    lua_getfield(state, -1, "path");
    const char* current = lua_tostring(state, -1);
    const std::string prefix = root.generic_string() + "/?.lua;" + root.generic_string() + "/?/init.lua;";
    const std::string path = prefix + (current ? current : "");
    lua_pop(state, 1);
    lua_pushlstring(state, path.data(), path.size());
    lua_setfield(state, -2, "path");
    lua_pop(state, 1);
    return true;
}

static void set_boolean(lua_State* state, const char* name, bool value) {
    lua_pushboolean(state, value);
    lua_setfield(state, -2, name);
}

static void set_integer(lua_State* state, const char* name, lua_Integer value) {
    lua_pushinteger(state, value);
    lua_setfield(state, -2, name);
}

static void set_string(lua_State* state, const char* name, const std::string& value) {
    lua_pushlstring(state, value.data(), value.size());
    lua_setfield(state, -2, name);
}

int main(int argc, char** argv) {
    Options options;
    bool anti_ia = false;
    bool show_help = false;
    if (!parse_arguments(argc, argv, options, anti_ia, show_help)) {
        if (show_help) return 0;
        usage(std::cerr);
        return 2;
    }
    if (options.native_loader && options.mode != "obfuscate") {
        std::cerr << "--native-loader requires --obfuscate\n";
        return 2;
    }
    if (options.native_loader && !options.has_secret) {
        std::cerr << "--native-loader requires --secret\n";
        return 2;
    }
    status(options.mode == "minify" ? "Starting minification." : "Starting obfuscation.");
    if (options.has_secret) {
        if (options.secret.empty()) {
            options.secret = generate_secret();
            if (!save_secret(options.secret_file, options.secret)) {
                std::cerr << "cannot save generated secret\n";
                return 1;
            }
            status("Generated a runtime secret and saved it to: " + options.secret_file);
        } else {
            status("Using the supplied runtime secret without displaying it.");
        }
    }
    status("Reading input: " + options.input);
    const std::string source = slurp(options.input);
    if (source.empty() && !fs::exists(options.input)) {
        std::cerr << "cannot read input\n";
        return 1;
    }
    status("Input loaded: " + std::to_string(source.size()) + " bytes.");
    status("Initializing the embedded Lua 5.4 runtime.");
    lua_State* state = luaL_newstate();
    if (!state) {
        std::cerr << "lua state failed\n";
        return 1;
    }
    luaL_openlibs(state);
    if (!configure_package_path(state, find_root(argv[0]))) {
        std::cerr << "cannot configure Lua module path\n";
        lua_close(state);
        return 1;
    }
    lua_getglobal(state, "require");
    lua_pushstring(state, options.mode == "minify" ? "src.minify" : "src.obfuscate");
    if (lua_pcall(state, 1, 1, 0) != LUA_OK) {
        std::cerr << lua_tostring(state, -1) << "\n";
        lua_close(state);
        return 1;
    }
    lua_getfield(state, -1, options.mode.c_str());
    if (!lua_isfunction(state, -1)) {
        std::cerr << "missing operation\n";
        lua_close(state);
        return 1;
    }
    lua_pushlstring(state, source.data(), source.size());
    int arguments = 1;
    StageContext stage_context{options.output.empty() ? fs::temp_directory_path() / "dazegghost-stage" : fs::path(options.output + ".stage")};
    if (options.mode == "obfuscate") {
        status("Transforming and sealing " + std::to_string(options.rounds) + " round(s).");
        lua_newtable(state);
        set_boolean(state, "anti_ia", anti_ia);
        set_string(state, "decoy_src", options.decoy);
        set_integer(state, "rounds", options.rounds);
        set_integer(state, "decoy_density", options.density);
        set_string(state, "mode", options.payload_mode);
        set_string(state, "runtime", options.runtime);
        if (options.has_min_chunk_size) set_integer(state, "min_chunk_size", options.min_chunk_size);
        if (options.has_max_chunk_size) set_integer(state, "max_chunk_size", options.max_chunk_size);
        set_integer(state, "noise_density", options.noise_density);
        set_integer(state, "max_output_bytes", static_cast<lua_Integer>(options.max_output_bytes));
        if (options.max_intermediate_bytes != 0) set_integer(state, "max_intermediate_bytes", static_cast<lua_Integer>(options.max_intermediate_bytes));
        set_boolean(state, "mix_original", options.mix_original);
        set_boolean(state, "flatten", options.flatten);
        set_boolean(state, "encode_strings", options.encode_strings);
        set_boolean(state, "split_strings", options.split_strings);
        set_boolean(state, "numbers_to_expressions", options.numbers_to_expressions);
        set_boolean(state, "constant_array", options.constant_array);
        set_boolean(state, "proxify_locals", options.proxify_locals);
        set_boolean(state, "anti_tamper", options.anti_tamper);
        if (options.has_watermark) set_string(state, "watermark", options.watermark);
        if (options.has_seed) set_integer(state, "seed", options.seed);
        if (options.has_secret) set_string(state, "secret", options.secret);
        lua_pushlightuserdata(state, &stage_context);
        lua_pushcclosure(state, stage_writer, 1);
        lua_setfield(state, -2, "stage_writer");
        arguments = 2;
    }
    if (lua_pcall(state, arguments, 1, 0) != LUA_OK) {
        const char* error = lua_tostring(state, -1);
        std::cerr << (error ? error : "Lua operation failed") << "\n";
        lua_close(state);
        return 1;
    }
    status("Transformation complete.");
    if (options.compress && options.mode == "obfuscate") {
        status("Packing the final payload and evaluating its size.");
        lua_getglobal(state, "require");
        lua_pushstring(state, "src.compress");
        if (lua_pcall(state, 1, 1, 0) != LUA_OK) {
            std::cerr << lua_tostring(state, -1) << "\n";
            lua_close(state);
            return 1;
        }
        lua_getfield(state, -1, "wrap");
        lua_pushvalue(state, -3);
        if (lua_pcall(state, 1, 1, 0) != LUA_OK) {
            std::cerr << lua_tostring(state, -1) << "\n";
            lua_close(state);
            return 1;
        }
        size_t original_length = 0;
        size_t compressed_length = 0;
        const char* original = lua_tolstring(state, -3, &original_length);
        const char* compressed = lua_tolstring(state, -1, &compressed_length);
        if (!original || !compressed || compressed_length >= original_length) {
            lua_pushvalue(state, -3);
            status("Packed loader was not smaller; keeping the original sealed output.");
        } else {
            status("Packed loader selected: " + std::to_string(compressed_length) + " bytes before newline.");
        }
    }
    size_t length = 0;
    const char* output = lua_tolstring(state, -1, &length);
    if (!output) {
        std::cerr << "operation returned no text\n";
        lua_close(state);
        return 1;
    }
    std::string result(output, length);
    if (result.empty() || result.back() != '\n') result.push_back('\n');
    lua_close(state);
    if (options.native_loader) {
        if (options.output.empty()) {
            std::cerr << "--native-loader requires --output\n";
            return 2;
        }
        const fs::path loader = find_root(argv[0]) / "dazeghost-loader";
        if (!fs::exists(loader)) {
            std::cerr << "native loader executable is not available; build dazeghost-loader first\n";
            return 1;
        }
        status("Embedding the payload into the native Lua 5.4 loader.");
        if (!append_native_payload(loader, options.output, result)) {
            std::cerr << "cannot create native loader output\n";
            return 1;
        }
        status("Completed native loader: " + std::to_string(fs::file_size(options.output)) + " bytes written.");
        return 0;
    }
    if (options.output.empty()) {
        status("Writing generated code to standard output.");
        std::cout.write(result.data(), static_cast<std::streamsize>(result.size()));
        return std::cout ? 0 : 1;
    }
    status("Writing output: " + options.output);
    std::ofstream file(options.output, std::ios::binary);
    if (!file) {
        std::cerr << "cannot write output\n";
        return 1;
    }
    file.write(result.data(), static_cast<std::streamsize>(result.size()));
    if (file) status("Completed: " + std::to_string(result.size()) + " bytes written.");
    return file ? 0 : 1;
}
