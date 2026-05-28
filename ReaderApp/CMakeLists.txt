set(APP_SOURCES
    src/main.mm
    src/AppDelegate.mm
    src/ReaderCanvasView.mm
    src/CoreTextMetrics.mm
    src/PreferencesWindowController.mm
    src/GlobalHotkey.mm
    src/KeyBindings.mm
    src/KeyRecorderButton.mm
    src/OnlineBookmarket.mm
    src/License.mm
    src/ActivationWindowController.mm
)

set(BS_JSON ${CMAKE_CURRENT_SOURCE_DIR}/Resources/bs.json)
set_source_files_properties(${BS_JSON} PROPERTIES
    MACOSX_PACKAGE_LOCATION "Resources")

set(APP_ICON ${CMAKE_CURRENT_SOURCE_DIR}/Resources/AppIcon.icns)
set_source_files_properties(${APP_ICON} PROPERTIES
    MACOSX_PACKAGE_LOCATION "Resources")

set(WECHAT_QR ${CMAKE_CURRENT_SOURCE_DIR}/Resources/wechat_qr.jpg)
set_source_files_properties(${WECHAT_QR} PROPERTIES
    MACOSX_PACKAGE_LOCATION "Resources")

add_executable(ReaderMac MACOSX_BUNDLE ${APP_SOURCES} ${APP_ICON} ${BS_JSON} ${WECHAT_QR})

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

# 共享 HMAC 密钥（与安卓 KeyGen 端必须一致）。
# 构建时通过 -DMOYU_SECRET_HEX=xxxx 注入；不传则源码里的占位生效（激活验签会失败但编译能过）。
# 真值见 /Users/apple/Desktop/Reader-Mac-Doc/secrets.txt
if(DEFINED MOYU_SECRET_HEX)
    target_compile_definitions(ReaderMac PRIVATE
        "MOYU_SECRET_HEX=\"${MOYU_SECRET_HEX}\"")
    message(STATUS "ReaderMac SECRET injected (len=${CMAKE_MATCH_COUNT})")
else()
    message(WARNING "MOYU_SECRET_HEX not provided; activation will NOT verify real keys")
endif()

target_link_libraries(ReaderMac PRIVATE
    reader_core
    "-framework Cocoa"
    "-framework AppKit"
    "-framework Foundation"
    "-framework CoreText"
    "-framework CoreGraphics"
    "-framework Carbon"
    "-framework Security"     # Keychain
    "-framework IOKit"        # IOPlatformUUID
)

# Rename the .app bundle to "摸鱼书摊.app" after build, so the Dock tooltip
# and Finder display name match. Keeps the inner binary as ReaderMac
# (matches CFBundleExecutable for ASCII-safety).
#
# CMake 把"资源拷贝"也实现成 POST_BUILD command，且在我们的 rename 之后才执行；
# 直接 rename 会导致资源被拷到刚被清空的 ReaderMac.app 里、最终的 摸鱼书摊.app
# 缺少 Resources。改用独立 custom_target 依赖 ReaderMac，target 内的 command
# 会在 ReaderMac 的全部 POST_BUILD 完成后才执行，保证资源已就位。
add_custom_target(MoyuShutanBundle ALL
    DEPENDS ReaderMac
    COMMAND ${CMAKE_COMMAND} -E rm -rf "${CMAKE_CURRENT_BINARY_DIR}/摸鱼书摊.app"
    COMMAND ${CMAKE_COMMAND} -E rename
            "${CMAKE_CURRENT_BINARY_DIR}/ReaderMac.app"
            "${CMAKE_CURRENT_BINARY_DIR}/摸鱼书摊.app"
    COMMENT "Renaming bundle to 摸鱼书摊.app"
)
