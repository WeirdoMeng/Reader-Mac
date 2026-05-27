set(APP_SOURCES
    src/main.mm
    src/AppDelegate.mm
    src/ReaderCanvasView.mm
    src/CoreTextMetrics.mm
)

add_executable(ReaderMac MACOSX_BUNDLE ${APP_SOURCES})

set_target_properties(ReaderMac PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/Resources/Info.plist
    MACOSX_BUNDLE_BUNDLE_NAME "Reader-Mac"
    MACOSX_BUNDLE_BUNDLE_VERSION "0.1.0"
    MACOSX_BUNDLE_LONG_VERSION_STRING "0.1.0"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.weirdomeng.ReaderMac"
)

target_compile_options(ReaderMac PRIVATE -fobjc-arc)

target_link_libraries(ReaderMac PRIVATE
    reader_core
    "-framework Cocoa"
    "-framework AppKit"
    "-framework Foundation"
    "-framework CoreText"
    "-framework CoreGraphics"
)
