// ReaderCore: cross-platform port of Reader/Book.h.
//
// HWND-based notification replaced with IBookListener (see Page base).
// _beginthreadex replaced with std::thread.

#pragma once

#include "reader/page.h"
#include "reader/types.h"

#include <map>
#include <string>
#include <thread>
#include <atomic>
#include <vector>

typedef struct chapter_item_t {
    int          index;
    std::wstring title;
    std::string  url;        // online book only
    int          size;       // online book: chapter byte size
    int          title_len;
} chapter_item_t;
typedef std::vector<chapter_item_t> chapters_t;

typedef enum book_type_t {
    book_unknown,
    book_text,
    book_epub,
    book_mobi,
    book_online
} book_type_t;

typedef struct file_data_t {
    void* data;
    int   size;
} file_data_t;
typedef std::map<std::string, file_data_t> filelist_t;

typedef struct manifest_t {
    std::string id;
    std::string href;
    std::string media_type;
} manifest_t;
typedef std::map<std::string, manifest_t*> manifests_t;

typedef std::vector<std::string> spines_t;

typedef struct navpoint_t {
    std::string id;
    std::string src;
    std::string text;
    int         order;
} navpoint_t;
typedef std::map<std::string, navpoint_t*> navpoints_t;

class Book : public Page {
public:
    Book();
    virtual ~Book();

    virtual book_type_t GetBookType(void) = 0;
    virtual BOOL        SaveBook(void) = 0;
    virtual BOOL        UpdateChapters(int offset) = 0;

    // Open from file (m_fileName must be set first via SetFileName).
    BOOL OpenBook(void);
    // Open from a pre-fetched buffer (Book takes ownership; free in CloseBook).
    BOOL OpenBook(char* data, int size);
    BOOL CloseBook(void);

    virtual BOOL IsLoading(void);

    void          SetFileName(const TCHAR* fileName);
    TCHAR*        GetFileName(void);
    wchar_t*      GetText(void);
    int           GetTextLength(void);
    chapters_t*   GetChapters(void);
    void          SetChapterRule(chapter_rule_t* rule);

    virtual void  JumpChapter(int index);
    virtual void  JumpPrevChapter(void);
    virtual void  JumpNextChapter(void);
    virtual int   GetCurChapterIndex(void);
    BOOL          GetChapterTitle(TCHAR* title, int size);
    BOOL          FormatText(wchar_t* p_data, int* p_len);

protected:
    virtual BOOL ParserBook(void) = 0;
    virtual BOOL DecodeText(const char* src, int srcsize, wchar_t** dst, int* dstsize);
    virtual BOOL IsChapterIndex(int index) override;
    virtual BOOL IsChapter(int index) override;
    virtual BOOL GetChapterInfo(int type, int* start, int* length) override;
    virtual BOOL IsValid(void) override;

    BOOL GetLine(wchar_t* text, int len, int* line_len, int* lf_len,
                 int* is_blank_line, int* prefix_blank_len, int* suffix_blank_len);
    void ForceKill(void);

protected:
    TCHAR              m_fileName[MAX_PATH];
    chapters_t         m_Chapters;
    char*              m_Data;
    int                m_Size;
    std::thread        m_Thread;
    std::atomic<bool>  m_bForceKill;
    std::atomic<bool>  m_IsLoading;
    chapter_rule_t*    m_Rule;
};
