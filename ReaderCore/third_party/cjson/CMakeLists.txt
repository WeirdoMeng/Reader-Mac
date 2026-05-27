add_library(cjson STATIC cJSON.c)
target_include_directories(cjson PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
set_target_properties(cjson PROPERTIES OUTPUT_NAME "cjson")
