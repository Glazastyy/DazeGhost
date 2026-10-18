cmake_minimum_required(VERSION 3.16)
project(dazeghost LANGUAGES C CXX)

if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()
if(POLICY CMP0169)
    cmake_policy(SET CMP0169 OLD)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(DAZEGHOST_LUA_INCLUDE_DIR "" CACHE PATH "Lua 5.4 include directory")
set(DAZEGHOST_LUA_LIBRARY "" CACHE FILEPATH "Lua 5.4 library file")
option(DAZEGHOST_USE_SYSTEM_LUA "Use a compatible system Lua 5.4 installation" ON)

function(dazegghost_is_lua54 include_dir result)
    set(valid FALSE)
    if(EXISTS "${include_dir}/lua.h")
        file(READ "${include_dir}/lua.h" header)
        if(header MATCHES "LUA_VERSION_MINOR_N[ \t]+4")
            set(valid TRUE)
        endif()
    endif()
    set(${result} ${valid} PARENT_SCOPE)
endfunction()

set(DAZEGHOST_LUA_INCLUDE_DIRS "")
set(DAZEGHOST_LUA_LIBRARIES "")
set(DAZEGHOST_LUA_LIBRARY_DIRS "")
set(DAZEGHOST_SYSTEM_LUA FALSE)

if(DAZEGHOST_USE_SYSTEM_LUA)
    find_package(PkgConfig QUIET)
    if(PkgConfig_FOUND)
        pkg_check_modules(LUA QUIET lua5.4)
        if(LUA_FOUND AND LUA_INCLUDE_DIRS)
            list(GET LUA_INCLUDE_DIRS 0 pkg_include_dir)
            dazegghost_is_lua54("${pkg_include_dir}" pkg_is_lua54)
            if(pkg_is_lua54)
                set(DAZEGHOST_LUA_INCLUDE_DIRS ${LUA_INCLUDE_DIRS})
                set(DAZEGHOST_LUA_LIBRARIES ${LUA_LIBRARIES})
                set(DAZEGHOST_LUA_LIBRARY_DIRS ${LUA_LIBRARY_DIRS})
                set(DAZEGHOST_SYSTEM_LUA TRUE)
            endif()
        endif()
    endif()

    if(NOT DAZEGHOST_SYSTEM_LUA)
        if(DAZEGHOST_LUA_INCLUDE_DIR AND DAZEGHOST_LUA_LIBRARY)
            dazegghost_is_lua54("${DAZEGHOST_LUA_INCLUDE_DIR}" explicit_is_lua54)
            if(explicit_is_lua54)
                set(DAZEGHOST_LUA_INCLUDE_DIRS "${DAZEGHOST_LUA_INCLUDE_DIR}")
                set(DAZEGHOST_LUA_LIBRARIES "${DAZEGHOST_LUA_LIBRARY}")
                set(DAZEGHOST_SYSTEM_LUA TRUE)
            endif()
        endif()
    endif()

    if(NOT DAZEGHOST_SYSTEM_LUA)
        find_path(system_lua_include_dir NAMES lua.h
            PATHS
                /usr/include/lua5.4
                /usr/local/include
                /usr/include
                /usr/include/${CMAKE_LIBRARY_ARCHITECTURE}
        )
        find_file(system_lua_library NAMES liblua5.4.so liblua5.4.so.0 liblua.so liblua.so.0
            PATHS
                /usr/local/lib
                /usr/lib
                /usr/lib/${CMAKE_LIBRARY_ARCHITECTURE}
        )
        if(system_lua_include_dir AND system_lua_library)
            dazegghost_is_lua54("${system_lua_include_dir}" discovered_is_lua54)
            if(discovered_is_lua54)
                set(DAZEGHOST_LUA_INCLUDE_DIRS "${system_lua_include_dir}")
                set(DAZEGHOST_LUA_LIBRARIES "${system_lua_library}")
                set(DAZEGHOST_SYSTEM_LUA TRUE)
            endif()
        endif()
    endif()
endif()

if(NOT DAZEGHOST_SYSTEM_LUA)
    message(STATUS "DazeGhost: no compatible system Lua 5.4 found; fetching the verified Lua source")
    include(FetchContent)
    FetchContent_Declare(lua54
        URL https://www.lua.org/ftp/lua-5.4.9.tar.gz
        URL_HASH SHA256=2335b6c582a52654f94612bf10d2f4672805d05329aa6568b1d8cd9e5c6fb8e6
    )
    FetchContent_Populate(lua54)
    file(GLOB DAZEGHOST_LUA_SOURCES CONFIGURE_DEPENDS "${lua54_SOURCE_DIR}/src/*.c")
    list(REMOVE_ITEM DAZEGHOST_LUA_SOURCES
        "${lua54_SOURCE_DIR}/src/lua.c"
        "${lua54_SOURCE_DIR}/src/luac.c"
    )
    add_library(dazegghost_lua STATIC ${DAZEGHOST_LUA_SOURCES})
    target_include_directories(dazegghost_lua PUBLIC "${lua54_SOURCE_DIR}/src")
    set(DAZEGHOST_LUA_INCLUDE_DIRS "${lua54_SOURCE_DIR}/src")
    set(DAZEGHOST_LUA_LIBRARIES dazegghost_lua)
    message(STATUS "DazeGhost: using bundled Lua 5.4")
else()
    message(STATUS "DazeGhost: using system Lua 5.4")
endif()

add_executable(dazeghost cpp/main.cpp)
add_executable(dazeghost-loader cpp/native_loader.cpp)

foreach(target dazeghost dazeghost-loader)
    set_target_properties(${target} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}"
    )
    target_include_directories(${target} PRIVATE ${DAZEGHOST_LUA_INCLUDE_DIRS})
    target_link_directories(${target} PRIVATE ${DAZEGHOST_LUA_LIBRARY_DIRS})
    target_link_libraries(${target} PRIVATE ${DAZEGHOST_LUA_LIBRARIES})
    if(LUA_CFLAGS_OTHER AND DAZEGHOST_SYSTEM_LUA)
        target_compile_options(${target} PRIVATE ${LUA_CFLAGS_OTHER})
    endif()
endforeach()
