// ReaderCore: HtmlParser implementation (libxml2-backed, platform-neutral).

#include "reader/html_parser.h"

#include <libxml/HTMLparser.h>
#include <libxml/HTMLtree.h>
#include <libxml/xpath.h>

#include <cstdlib>
#include <cstring>

HtmlParser::HtmlParser()  { xmlInitParser(); }
HtmlParser::~HtmlParser() { xmlCleanupParser(); }

HtmlParser* HtmlParser::Instance() {
    static HtmlParser* s = nullptr;
    if (!s) s = new HtmlParser;
    return s;
}

void HtmlParser::ReleaseInstance() {
    static bool released = false;
    if (released) return;
    delete Instance();
    released = true;
}

char* HtmlParser::CreateContent(const char* xml) {
    if (!xml) return nullptr;
    char* content = (char*)malloc(strlen(xml) + 1);
    if (!content) return nullptr;
    const char* in = xml;
    char* out = content;
    while (*in) {
        switch (*in) {
            case ' ': case '\r': case '\t': case '\n': break;
            default: *out++ = *in; break;
        }
        ++in;
    }
    *out = 0;
    return content;
}

void HtmlParser::ReleaseContent(char* content) {
    if (content) free(content);
}

#define GOTO_STOP(s) if ((s) && *(s)) goto _stop

int HtmlParser::HtmlParseByXpath(const char* html, int len,
                                 const std::string& xpath,
                                 std::vector<std::string>& value,
                                 int* stop, int clear) {
    int i;
    xmlDocPtr doc = nullptr;
    xmlXPathContextPtr xpathCtx = nullptr;
    xmlXPathObjectPtr  xpathObj = nullptr;
    xmlNodeSetPtr      nodeset  = nullptr;
    xmlChar*           keyword  = nullptr;
    char*              content  = nullptr;

    GOTO_STOP(stop);
    doc = htmlReadMemory(html, len, nullptr, nullptr, HTML_PARSE_RECOVER);
    if (!doc) return 1;

    GOTO_STOP(stop);
    xpathCtx = xmlXPathNewContext(doc);
    if (!xpathCtx) { xmlFreeDoc(doc); return 1; }

    GOTO_STOP(stop);
    xpathObj = xmlXPathEvalExpression(BAD_CAST xpath.c_str(), xpathCtx);
    xmlXPathFreeContext(xpathCtx);
    xpathCtx = nullptr;
    if (!xpathObj) { xmlFreeDoc(doc); return 1; }

    GOTO_STOP(stop);

    if (xmlXPathNodeSetIsEmpty(xpathObj->nodesetval)) {
        xmlXPathFreeObject(xpathObj);
        xmlFreeDoc(doc);
        return 0;
    }

    nodeset = xpathObj->nodesetval;
    for (i = 0; i < nodeset->nodeNr; ++i) {
        GOTO_STOP(stop);
        keyword = xmlNodeGetContent(nodeset->nodeTab[i]);
        if (clear) {
            if (keyword) {
                content = CreateContent((const char*)keyword);
                if (content) {
                    value.push_back(content);
                    ReleaseContent(content);
                }
            }
        } else if (keyword) {
            value.push_back((const char*)keyword);
        }
        if (keyword) xmlFree(keyword);
    }
    xmlXPathFreeObject(xpathObj);
    xmlFreeDoc(doc);
    return 0;

_stop:
    if (xpathObj) xmlXPathFreeObject(xpathObj);
    if (xpathCtx) xmlXPathFreeContext(xpathCtx);
    if (doc)      xmlFreeDoc(doc);
    return 1;
}

int HtmlParser::HtmlParseBegin(const char* html, int len,
                               void** pdoc, void** pctx, int* stop) {
    xmlDocPtr           doc = nullptr;
    xmlXPathContextPtr  ctx = nullptr;

    *pdoc = nullptr;
    *pctx = nullptr;

    GOTO_STOP(stop);
    doc = htmlReadMemory(html, len, nullptr, nullptr, HTML_PARSE_RECOVER);
    if (!doc) return 1;

    GOTO_STOP(stop);
    ctx = xmlXPathNewContext(doc);
    if (!ctx) { xmlFreeDoc(doc); return 1; }

    *pdoc = doc;
    *pctx = ctx;
    return 0;

_stop:
    if (ctx) xmlXPathFreeContext(ctx);
    if (doc) xmlFreeDoc(doc);
    return 1;
}

int HtmlParser::HtmlParseByXpath(void* doc_, void* ctx_,
                                 const std::string& xpath,
                                 std::vector<std::string>& value,
                                 int* stop, int clear) {
    if (!doc_ || !ctx_) return 1;
    int i;
    xmlXPathContextPtr xpathCtx = (xmlXPathContextPtr)ctx_;
    xmlXPathObjectPtr  xpathObj = nullptr;
    xmlNodeSetPtr      nodeset  = nullptr;
    xmlChar*           keyword  = nullptr;
    char*              content  = nullptr;

    GOTO_STOP(stop);
    xpathObj = xmlXPathEvalExpression(BAD_CAST xpath.c_str(), xpathCtx);
    if (!xpathObj) return 1;

    if (xmlXPathNodeSetIsEmpty(xpathObj->nodesetval)) {
        xmlXPathFreeObject(xpathObj);
        return 0;
    }

    nodeset = xpathObj->nodesetval;
    for (i = 0; i < nodeset->nodeNr; ++i) {
        GOTO_STOP(stop);
        keyword = xmlNodeGetContent(nodeset->nodeTab[i]);
        if (clear) {
            if (keyword) {
                content = CreateContent((const char*)keyword);
                if (content) {
                    value.push_back(content);
                    ReleaseContent(content);
                }
            }
        } else if (keyword) {
            value.push_back((const char*)keyword);
        }
        if (keyword) xmlFree(keyword);
    }
    xmlXPathFreeObject(xpathObj);
    return 0;

_stop:
    if (xpathObj) xmlXPathFreeObject(xpathObj);
    return 1;
}

int HtmlParser::HtmlParseEnd(void* doc_, void* ctx_) {
    if (ctx_) xmlXPathFreeContext((xmlXPathContextPtr)ctx_);
    if (doc_) xmlFreeDoc((xmlDocPtr)doc_);
    return 0;
}

int HtmlParser::FormatHtml(char* html, int len, char** htmlfmt, int* fmtlen) {
    xmlChar* format_str = nullptr;
    int size = 0;

    xmlKeepBlanksDefault(0);
    xmlIndentTreeOutput = 0;
    xmlDocPtr doc = htmlReadMemory(html, len, nullptr, nullptr,
                                   HTML_PARSE_RECOVER | HTML_PARSE_NOBLANKS);
    if (doc) {
        htmlDocDumpMemoryFormat(doc, &format_str, &size, 1);
        xmlFreeDoc(doc);
        if (!format_str || size <= 0) {
            if (format_str) { xmlFree(format_str); format_str = nullptr; }
            size = 0;
        }
    }

    xmlKeepBlanksDefault(1);
    xmlIndentTreeOutput = 0;

    *htmlfmt = (char*)format_str;
    *fmtlen = size;
    return 0;
}

void HtmlParser::FreeFormat(char* htmlfmt) {
    xmlFree(htmlfmt);
}
