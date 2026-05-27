// ReaderCore: OnlineBook stub. See header for milestone note.

#include "reader/online_book.h"

OnlineBook::OnlineBook() = default;
OnlineBook::~OnlineBook() {
    ForceKill();
    for (auto h : m_hRequestList) hapi_cancel(h);
    m_hRequestList.clear();
}

book_type_t OnlineBook::GetBookType(void) { return book_online; }
BOOL OnlineBook::SaveBook(void)               { return FALSE; }
BOOL OnlineBook::UpdateChapters(int /*offset*/) { return FALSE; }

BOOL OnlineBook::ParserBook(void) {
    // TODO: full crawler chain (book source → search → chapter list →
    // content fetch → cache to .online/) — see upstream OnlineBook.cpp.
    return FALSE;
}

int OnlineBook::CheckUpdate(olbook_checkupdate_callback cb, void* arg) {
    m_cb  = cb;
    m_arg = arg;
    if (cb) cb(0, /*err=*/-1, arg);  // not implemented yet
    return -1;
}
