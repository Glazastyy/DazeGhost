cmake_minimum_required(VERSION 3.16)
project(dazeghost CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(LUA REQUIRED lua5.4)

add_executable(dazeghost cpp/main.cpp)
target_include_directories(dazeghost PRIVATE ${LUA_INCLUDE_DIRS})
target_link_libraries(dazeghost PRIVATE ${LUA_LIBRARIES})
target_compile_options(dazeghost PRIVATE ${LUA_CFLAGS_OTHER})
