// ReaderCore: cross-platform port of Reader/TextBook.cpp.

#include "reader/text_book.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <regex>

wchar_t TextBook::m_ValidChapter[] = {
    L' ', L'\t',
    L'0', L'1', L'2', L'3', L'4',
    L'5', L'6', L'7', L'8', L'9',
    L'零', L'一', L'二', L'三', L'四',
    L'五', L'六', L'七', L'八', L'九',
    L'十', L'百', L'千', L'万', L'亿',
    L'壹', L'贰', L'叁', L'肆',
    L'伍', L'陆', L'柒', L'捌', L'玖',
    L'拾', L'佰', L'仟', L'萬', L'億',
    L'两',
    0x3000
};

TextBook::TextBook() = default;

TextBook::~TextBook() {
    ForceKill();
}

book_type_t TextBook::GetBookType(void) {
    return book_text;
}

BOOL TextBook::SaveBook(void) {
    FILE* fp = _tfopen(m_fileName, _T("wb"));
    if (!fp) return FALSE;
    // Write UTF-16LE BOM, then 2-byte UTF-16 (compatible with original Win
    // format). On macOS wchar_t is 4 bytes — narrow each code point to 16 bits
    // (no surrogate-pair handling for now; sufficient for BMP text).
    std::fwrite("\xff\xfe", 2, 1, fp);
    for (int i = 0; i < m_Length; ++i) {
        uint16_t u = (uint16_t)(m_Text[i] & 0xFFFF);
        std::fwrite(&u, sizeof(uint16_t), 1, fp);
    }
    std::fclose(fp);
    return TRUE;
}

BOOL TextBook::UpdateChapters(int offset) {
    for (auto& c : m_Chapters) {
        if (c.index > m_Index) {
            c.index += offset;
            if (c.index < 0) c.index = 0;
        }
    }
    return TRUE;
}

BOOL TextBook::ParserBook(void) {
    if (!ReadBook())     { CloseBook(); return FALSE; }
    if (!ParserChapters()) { CloseBook(); return FALSE; }
    return TRUE;
}

BOOL TextBook::ReadBook(void) {
    FILE* fp = nullptr;
    char* buf = nullptr;
    int len = 0;
    BOOL ret = FALSE;

    if (m_Data && m_Size > 0) {
        buf = m_Data;
        len = m_Size;
    } else if (m_fileName[0]) {
        fp = _tfopen(m_fileName, _T("rb"));
        if (!fp) goto end;
        std::fseek(fp, 0, SEEK_END);
        len = (int)std::ftell(fp);
        std::fseek(fp, 0, SEEK_SET);
        buf = (char*)std::malloc((size_t)(len + 2));
        if (!buf) goto end;
        buf[len] = 0;
        buf[len + 1] = 0;
        if ((int)std::fread(buf, 1, (size_t)len, fp) != len) goto end;
    } else {
        goto end;
    }

    if (!DecodeText(buf, len, &m_Text, &m_Length)) goto end;
    if (m_bForceKill.load()) goto end;
    ret = TRUE;

end:
    if (fp) std::fclose(fp);
    if (buf && buf != m_Data) std::free(buf);
    if (m_Data) m_Data = nullptr;
    m_Size = 0;
    return ret;
}

BOOL TextBook::ParserChapters(void) {
    // If no rule is set, use default heuristic. Original behavior returned
    // FALSE here; we keep the same on rule_t pointer.
    if (!m_Rule) return ParserChaptersDefault();
    m_Chapters.clear();
    switch (m_Rule->rule) {
        case 0: return ParserChaptersDefault();
        case 1: return ParserChaptersKeyword();
        case 2: return ParserChaptersRegex();
    }
    return FALSE;
}

BOOL TextBook::ParserChaptersDefault(void) {
    wchar_t* text = m_Text;
    wchar_t title[MAX_CHAPTER_LENGTH] = {0};
    int line_size;
    chapter_item_t chapter;

    while (TRUE) {
        if (m_bForceKill.load()) return FALSE;
        if (!GetLine(text, m_Length - (int)(text - m_Text),
                     &line_size, nullptr, nullptr, nullptr, nullptr)) {
            break;
        }

        BOOL bFound = FALSE;
        int idx_1 = -1, idx_2 = -1;
        for (int i = 0; i < line_size; ++i) {
            if (text[i] == L'第') idx_1 = i;
            if (idx_1 > -1
                && ((line_size > i + 1 && (text[i + 1] == L' ' || text[i + 1] == L'\t'))
                    || (line_size > i + 1 && (text[i + 1] == 0x3000 || text[i + 1] == 0xA0))
                    || line_size <= i + 1
                    || (line_size > i + 1 && (text[i + 1] == L'：' || text[i + 1] == L':')))) {
                if (text[i] == L'卷' || text[i] == L'章'
                    || text[i] == L'部' || text[i] == L'节') {
                    idx_2 = i; bFound = TRUE; break;
                }
            }
            if (idx_1 == -1 && line_size > i + 2 && text[i] == L'楔' && text[i + 1] == L'子'
                && (text[i + 2] == L' ' || text[i + 2] == L'\t'
                    || text[i + 2] == 0x3000 || line_size <= i + 1)) {
                idx_1 = i; idx_2 = line_size - 1; bFound = TRUE; break;
            }
            if (idx_1 == -1 && line_size > i + 2 && text[i] == L'序' && text[i + 1] == L'章'
                && (text[i + 2] == L' ' || text[i + 2] == L'\t'
                    || text[i + 2] == 0x3000 || line_size <= i + 1)) {
                idx_1 = i; idx_2 = line_size - 1; bFound = TRUE; break;
            }
        }
        if (bFound && (text[idx_1] == L'楔' || text[idx_1] == L'序'
                       || IsChapterText(text + idx_1 + 1, idx_2 - idx_1 - 1))) {
            int title_len = line_size - idx_1 < (MAX_CHAPTER_LENGTH - 1)
                                ? line_size - idx_1
                                : MAX_CHAPTER_LENGTH - 1;
            std::memcpy(title, text + idx_1, (size_t)title_len * sizeof(wchar_t));
            title[title_len] = 0;
            chapter.index = (int)(text - m_Text);
            chapter.title = title;
            chapter.title_len = title_len;
            m_Chapters.push_back(chapter);
        }

        text += line_size + 1;  // +1 for \n
    }
    return TRUE;
}

BOOL TextBook::ParserChaptersKeyword(void) {
    if (!m_Rule) return FALSE;
    wchar_t* text = m_Text;
    wchar_t title[MAX_CHAPTER_LENGTH] = {0};
    int line_size;
    chapter_item_t chapter;
    int cmplen = (int)std::wcslen(m_Rule->keyword);

    while (TRUE) {
        if (m_bForceKill.load()) return FALSE;
        if (!GetLine(text, m_Length - (int)(text - m_Text),
                     &line_size, nullptr, nullptr, nullptr, nullptr)) {
            break;
        }
        if (cmplen <= line_size) {
            BOOL bFound = FALSE;
            int idx_1 = -1;
            for (int i = 0; i < line_size; ++i) {
                if (std::wcsncmp(text + i, m_Rule->keyword, (size_t)cmplen) == 0) {
                    idx_1 = i; bFound = TRUE; break;
                }
            }
            if (bFound) {
                int title_len = line_size - idx_1 < (MAX_CHAPTER_LENGTH - 1)
                                    ? line_size - idx_1
                                    : MAX_CHAPTER_LENGTH - 1;
                std::memcpy(title, text + idx_1, (size_t)title_len * sizeof(wchar_t));
                title[title_len] = 0;
                chapter.index = (int)(text - m_Text);
                chapter.title = title;
                chapter.title_len = title_len;
                m_Chapters.push_back(chapter);
            }
        }
        text += line_size + 1;
    }
    return TRUE;
}

BOOL TextBook::ParserChaptersRegex(void) {
    if (!m_Rule) return FALSE;
    wchar_t title[MAX_CHAPTER_LENGTH] = {0};
    chapter_item_t chapter;
    int offset = 0;
    std::wcmatch cm;
    std::wregex* e = nullptr;
    wchar_t* text = m_Text;
    try {
        e = new std::wregex(m_Rule->regex);
    } catch (...) {
        delete e;
        return FALSE;
    }
    while (std::regex_search(text, cm, *e, std::regex_constants::format_first_only)) {
        if (m_bForceKill.load()) break;
        int title_len = (int)cm.length() < (MAX_CHAPTER_LENGTH - 1)
                            ? (int)cm.length()
                            : MAX_CHAPTER_LENGTH - 1;
        std::memcpy(title, cm.str().c_str(), (size_t)title_len * sizeof(wchar_t));
        title[title_len] = 0;
        chapter.index = offset + (int)cm.position();
        chapter.title = title;
        chapter.title_len = title_len;
        m_Chapters.push_back(chapter);
        text   += cm.position() + cm.length();
        offset += (int)cm.position() + (int)cm.length();
    }
    delete e;
    return TRUE;
}

BOOL TextBook::IsChapterText(wchar_t* text, int len) {
    if (!text || len <= 0) return FALSE;
    const size_t valid_n = sizeof(m_ValidChapter) / sizeof(m_ValidChapter[0]);
    for (int i = 0; i < len; ++i) {
        BOOL bFound = FALSE;
        for (size_t j = 0; j < valid_n; ++j) {
            if (text[i] == m_ValidChapter[j]) { bFound = TRUE; break; }
        }
        if (!bFound) return FALSE;
    }
    return TRUE;
}
