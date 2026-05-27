add_library(minizip STATIC
    ioapi.c
    unzip.c
    zip.c
    mztools.c
)
target_include_directories(minizip PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

find_package(ZLIB REQUIRED)
target_link_libraries(minizip PUBLIC ZLIB::ZLIB)

target_compile_definitions(minizip PRIVATE
    _LARGEFILE64_SOURCE
    _FILE_OFFSET_BITS=64
)

# Apple Clang 对 unzip.c 中的旧式 K&R 风格代码会给警告
target_compile_options(minizip PRIVATE
    -Wno-deprecated-non-prototype
    -Wno-implicit-function-declaration
    -Wno-incompatible-pointer-types
)
