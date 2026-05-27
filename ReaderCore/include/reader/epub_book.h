// ReaderCore: cross-platform port of Reader/EpubBook.h.
// Gdiplus::Bitmap dependency removed — cover stored as raw image bytes;
// UI layer decodes via NSImage / CGImage on macOS, GDI+ on Windows.

#pragma once

#include "reader/book.h"

#include <cstdint>
#include <map>
#include <string>
#include <vector>

typedef struct epub_t {
    std::string  path;
    std::string  ocf;
    std::string  opf;
    std::string  ncx;
    manifests_t  manifests;
    spines_t     spines;
    navpoints_t  navpoints;
} epub_t;

class EpubBook : public Book {
public:
    EpubBook();
    virtual ~EpubBook();

    book_type_t GetBookType(void) override;
    BOOL        SaveBook(void) override;
    BOOL        UpdateChapters(int offset) override;

    // Cover access for UI.
    const std::vector<uint8_t>& GetCoverData(void) const { return m_CoverData; }
    const std::string&          GetCoverMediaType(void) const { return m_CoverMediaType; }

protected:
    BOOL ParserBook(void) override;
    int  GetTextBeginIndex(void) override;
    BOOL HasCover(void) const override { return !m_CoverData.empty(); }

    void FreeFilelist(void);
    BOOL UnzipBook(void);
    BOOL ParserOcf(epub_t& epub);
    BOOL ParserOpf(epub_t& epub);
    BOOL ParserNcx(epub_t& epub);
    BOOL ParserOps(file_data_t* fdata, wchar_t** text, int* len,
                   wchar_t** title, int* tlen, BOOL parsertitle);
    BOOL ParserChapters(epub_t& epub);
    BOOL ParserCover(epub_t& epub);

private:
    std::vector<uint8_t> m_CoverData;       // raw image bytes (jpg/png/gif)
    std::string          m_CoverMediaType;  // e.g. "image/jpeg"
    filelist_t           m_flist;
};
