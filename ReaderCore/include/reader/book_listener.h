// ReaderCore: book event listener.
//
// Replaces Windows PostMessage(hWnd, WM_BOOK_EVENT, ...) calls that the
// original Book/OnlineBook used to talk to the host window. The host
// (macOS UI, CLI smoke test, unit test) implements this interface; the
// engine fires it on its worker thread, so the implementation must be
// thread-safe.

#pragma once

#include "reader/platform.h"

namespace reader {

enum class BookEvent {
    OpenStart,           // ParserBook() began
    OpenFinished,        // ParserBook() finished (param1 = success/fail code)
    ChaptersUpdated,     // chapter list changed (online book)
    NewVersionAvailable, // (upgrade) latest != current
    Redraw,              // engine wants the canvas redrawn (param1 = draw_type)
    SaveCache,           // request the host to persist .cache.dat
    LoadingFrame,        // play the loading animation (online book)
    ChapterTitleChanged,
};

class IBookListener {
public:
    virtual ~IBookListener() = default;

    // Called by the engine (often on a background thread) to notify the host.
    // The host implementation is responsible for marshaling onto the UI
    // thread before touching UI state.
    virtual void on_book_event(BookEvent evt,
                               intptr_t param1 = 0,
                               intptr_t param2 = 0) = 0;
};

}  // namespace reader
