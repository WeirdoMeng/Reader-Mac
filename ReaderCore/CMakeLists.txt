cmake_minimum_required(VERSION 3.20)
project(ReaderCore CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "Universal binary" FORCE)
endif()
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "" FORCE)
endif()

set(THIRD_PARTY_INSTALL "${CMAKE_CURRENT_SOURCE_DIR}/third_party/_install")

# ---------------- 内嵌源码的轻量库 ----------------
add_subdirectory(third_party/cjson)
add_subdirectory(third_party/miniz)
add_subdirectory(third_party/minizip)

# ---------------- 系统库 ----------------
# zlib：macOS SDK 自带（libz）
find_package(ZLIB REQUIRED)

# libxml2：macOS SDK 自带
find_library(XML2_LIB xml2 REQUIRED)
execute_process(COMMAND xcrun --show-sdk-path OUTPUT_VARIABLE SDK_PATH OUTPUT_STRIP_TRAILING_WHITESPACE)
set(XML2_INCLUDE_DIR "${SDK_PATH}/usr/include/libxml2")

# ---------------- libmobi（vendored）----------------
# 用 libmobi 自带的 CMake，但关掉 shared / encryption / xmlwriter 简化
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(TOOLS_STATIC ON CACHE BOOL "" FORCE)
set(USE_ENCRYPTION OFF CACHE BOOL "" FORCE)
set(USE_LIBXML2 ON CACHE BOOL "" FORCE)
set(USE_ZLIB ON CACHE BOOL "" FORCE)
set(USE_XMLWRITER ON CACHE BOOL "" FORCE)
# libmobi 的 CMakeLists 用了 LIBMOBI_SOURCE_DIR 但没定义；先 set 上
set(LIBMOBI_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libmobi)
add_subdirectory(third_party/libmobi)
