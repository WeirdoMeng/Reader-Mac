// ReaderCore: cross-platform port of Reader/MobiBook.h.
// Uses libmobi for MOBI parsing; cover stored as raw bytes.

#pragma once

#include "reader/book.h"

#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include <mobi.h>

typedef struct mobi_t {
    std::string path;
    std::string opf;
    std::string ncx;
    manifests_t manifests;
    spines_t    spines;
    navpoints_t navpoints;
} mobi_t;

class MobiBook : public Book {
public:
    MobiBook();
    virtual ~MobiBook();

    book_type_t GetBookType(void) override;
    BOOL        SaveBook(void) override;
    BOOL        UpdateChapters(int offset) override;

    const std::vector<uint8_t>& GetCoverData(void) const { return m_CoverData; }
    const std::string&          GetCoverMediaType(void) const { return m_CoverMediaType; }

protected:
    BOOL ParserBook(void) override;
    int  GetTextBeginIndex(void) override;
    BOOL HasCover(void) const override { return !m_CoverData.empty(); }

    void FreeFilelist(void);
    BOOL UnzipBook(MOBIRawml* rawml, MOBIData* m, mobi_t& mobi);
    BOOL ParserOpf(mobi_t& mobi);
    BOOL ParserNcx(mobi_t& mobi);
    BOOL ParserOps(file_data_t* fdata, wchar_t** text, int* len,
                   wchar_t** title, int* tlen, BOOL parsertitle);
    BOOL ParserChapters(mobi_t& mobi);
    BOOL ParserCover(mobi_t& mobi, MOBIData* m);

private:
    std::vector<uint8_t> m_CoverData;
    std::string          m_CoverMediaType;
    filelist_t           m_flist;
};
