// ReaderCore: cross-platform port of Reader/TextBook.h.

#pragma once

#include "reader/book.h"

class TextBook : public Book {
public:
    TextBook();
    virtual ~TextBook();

    book_type_t GetBookType(void) override;
    BOOL        SaveBook(void) override;
    BOOL        UpdateChapters(int offset) override;

protected:
    BOOL ParserBook(void) override;
    BOOL ReadBook(void);
    BOOL ParserChapters(void);
    BOOL ParserChaptersDefault(void);
    BOOL ParserChaptersKeyword(void);
    BOOL ParserChaptersRegex(void);
    BOOL IsChapterText(wchar_t* text, int len);

protected:
    static wchar_t m_ValidChapter[];
};
