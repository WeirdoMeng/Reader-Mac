set(APP_SOURCES
    src/main.mm
    src/AppDelegate.mm
    src/ReaderCanvasView.mm
    src/CoreTextMetrics.mm
    src/PreferencesWindowController.mm
    src/GlobalHotkey.mm
    src/KeyBindings.mm
    src/KeyRecorderButton.mm
)

set(APP_ICON ${CMAKE_CURRENT_SOURCE_DIR}/Resources/AppIcon.icns)
set_source_files_properties(${APP_ICON} PROPERTIES
    MACOSX_PACKAGE_LOCATION "Resources")

add_executable(ReaderMac MACOSX_BUNDLE ${APP_SOURCES} ${APP_ICON})

set_target_properties(ReaderMac PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/Resources/Info.plist
    MACOSX_BUNDLE_BUNDLE_NAME "摸鱼书摊"
    MACOSX_BUNDLE_BUNDLE_VERSION "0.2.0"
    MACOSX_BUNDLE_LONG_VERSION_STRING "0.2.0"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.2.0"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.weirdomeng.MoyuShutan"
    MACOSX_BUNDLE_ICON_FILE "AppIcon"
)

target_compile_options(ReaderMac PRIVATE -fobjc-arc)

target_link_libraries(ReaderMac PRIVATE
    reader_core
    "-framework Cocoa"
    "-framework AppKit"
    "-framework Foundation"
    "-framework CoreText"
    "-framework CoreGraphics"
    "-framework Carbon"
)
