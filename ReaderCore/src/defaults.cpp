// Cross-platform default header_t. Adapted from Cache::default_header() in
// the original project, with Windows-specific font/window-style choices
// replaced by neutral values the UI layer can override.

#include "reader/defaults.h"

#include <cstring>

namespace reader {

void fill_default_header(header_t* header) {
    if (!header) return;
    std::memset(header, 0, sizeof(header_t));

    header->item_id = -1;

    // ---- default font ----
    // lfHeight is in *device pixels*, negative means "this is point-relative".
    // The macOS UI layer translates this into NSFont size; for CLI/unit tests
    // a positive logical height is enough.
    header->font.lfHeight = -16;
    header->font.lfWeight = FW_NORMAL;
    // Pick a face that exists on both Win and Mac; UI may override.
    const wchar_t kFace[] = L"PingFang SC";
    std::memcpy(header->font.lfFaceName, kFace, sizeof(kFace));
    header->font_color = 0x000000;

    header->font_title = header->font;
    header->font_color_title = 0x000000;
    header->use_same_font = 1;

    // ---- window placement (purely advisory; UI may override) ----
    header->placement.length  = sizeof(WINDOWPLACEMENT);
    header->placement.showCmd = 1;
    header->placement.ptMinPosition.x = -1;
    header->placement.ptMinPosition.y = -1;
    header->placement.ptMaxPosition.x = -1;
    header->placement.ptMaxPosition.y = -1;
    header->placement.rcNormalPosition.left   = 0;
    header->placement.rcNormalPosition.top    = 0;
    header->placement.rcNormalPosition.right  = DEFAULT_APP_WIDTH;
    header->placement.rcNormalPosition.bottom = DEFAULT_APP_HEIGHT;

    header->fs_placement = header->placement;

    // ---- styling (cross-platform values; UI maps to NSWindow.styleMask) ----
    header->style      = 0;
    header->exstyle    = 0;
    header->fs_style   = 0;
    header->fs_exstyle = 0;

    // ---- colors ----
    header->bg_color = 0x00FFFFFF;  // white
    header->alpha    = 0xFF;

    // ---- typography ----
    header->char_gap        = 1;
    header->line_gap        = 5;
    header->paragraph_gap   = 7;
    header->left_line_count = 0;
    header->internal_border.left   = 12;
    header->internal_border.top    = 12;
    header->internal_border.right  = 12;
    header->internal_border.bottom = 12;

    // ---- version string (overwritten by Cache when persistence lands) ----
    const wchar_t kVer[] = L"1.0.0";
    std::memcpy(header->version, kVer, sizeof(kVer));

    // ---- behavior knobs ----
    header->wheel_speed      = ws_single_line;
    header->page_mode        = 1;
    header->autopage_mode    = 0;
    header->uElapse          = 3000;
    header->bg_image.enable  = FALSE;
    header->disable_lrhide   = 1;
    header->disable_eschide  = 1;
    header->show_systray     = 0;
    header->hide_taskbar     = 0;
    header->word_wrap        = 0;
    header->line_indent      = 1;
    header->blank_lines      = 1;
    header->chapter_page     = 0;
    header->global_key       = 0;
    header->meun_font_follow = 0;

    header->chapter_rule.rule = 0;

    for (int i = 0; i < MAX_CUST_COLOR_COUNT; ++i) {
        header->cust_colors[i] = 0x00FFFFFF;
    }
}

}  // namespace reader
