// ReaderCore: cross-platform OnlineBook port.
//
// MVP NOTE: This is a *stub* — the engine accepts an OnlineBook instance and
// can wire it into the UI's book-type dispatch, but the actual book-source
// crawler chain (1800+ lines in the upstream codebase, deeply coupled with
// the original Win32 UI message pump) is left for a later milestone, after
// the macOS UI layer can display loading animations and error dialogs.

#pragma once

#include "reader/book.h"
#include "reader/https.h"

#include <set>
#include <string>

typedef void (*olbook_checkupdate_callback)(int is_update, int err, void* param);

class OnlineBook : public Book {
public:
    OnlineBook();
    virtual ~OnlineBook();

    book_type_t GetBookType(void) override;
    BOOL        SaveBook(void) override;
    BOOL        UpdateChapters(int offset) override;

    void SetBookSource(book_source_t* src) { m_Booksrc = src; }
    int  CheckUpdate(olbook_checkupdate_callback cb, void* arg);

protected:
    BOOL ParserBook(void) override;

protected:
    std::set<req_handler_t> m_hRequestList;
    char        m_MainPage[1024]     = {0};
    char        m_ChapterPage[1024]  = {0};
    TCHAR       m_BookName[256]      = {0};
    char        m_Host[1024]         = {0};
    uint64_t    m_UpdateTime         = 0;
    book_source_t* m_Booksrc         = nullptr;
    olbook_checkupdate_callback m_cb = nullptr;
    void*       m_arg                = nullptr;
};
