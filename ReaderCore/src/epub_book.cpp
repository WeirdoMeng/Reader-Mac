// ReaderCore: cross-platform EpubBook implementation.
// Uses minizip (POSIX iowin32 alternative: stock fopen-based ioapi) and
// libxml2 for OPF/NCX/XHTML parsing.

#include "reader/epub_book.h"
#include "reader/utils.h"

#include "unzip.h"
#include <libxml/HTMLparser.h>
#include <libxml/HTMLtree.h>
#include <libxml/xmlreader.h>
#include <libxml/xpath.h>

#include <cstdlib>
#include <cstring>
#include <string>

EpubBook::EpubBook() {
    xmlInitParser();
}

EpubBook::~EpubBook() {
    ForceKill();
    FreeFilelist();
    // xmlCleanupParser is process-global; safe to skip here since
    // HtmlParser singleton also touches it.
}

book_type_t EpubBook::GetBookType(void) { return book_epub; }
BOOL EpubBook::SaveBook(void)               { return FALSE; }
BOOL EpubBook::UpdateChapters(int /*offset*/) { return FALSE; }

int EpubBook::GetTextBeginIndex(void) {
    return HasCover() ? 1 : 0;
}

void EpubBook::FreeFilelist(void) {
    for (auto& kv : m_flist) {
        std::free(kv.second.data);
    }
    m_flist.clear();
}

// Convert wchar_t path to UTF-8 since minizip's POSIX ioapi takes char*.
static std::string wpath_to_utf8(const wchar_t* p) {
    int n = 0;
    char* u = utf16_to_utf8(p, (int)std::wcslen(p), &n);
    std::string out;
    if (u) { out.assign(u, (size_t)n); free_buffer(u); }
    return out;
}

BOOL EpubBook::UnzipBook(void) {
    std::string utf8_path = wpath_to_utf8(m_fileName);
    unzFile uf = unzOpen64(utf8_path.c_str());
    if (!uf) return FALSE;

    unz_global_info gi = {0, 0};
    int err = unzGetGlobalInfo(uf, &gi);
    if (err != UNZ_OK) { unzClose(uf); return FALSE; }

    FreeFilelist();

    for (uLong i = 0; i < gi.number_entry; ++i) {
        unz_file_info64 file_info = {};
        char filename_inzip[1024] = {0};
        err = unzGetCurrentFileInfo64(uf, &file_info, filename_inzip,
                                      sizeof(filename_inzip), nullptr, 0, nullptr, 0);
        if (err != UNZ_OK) break;

        // skip directories
        size_t flen = file_info.size_filename;
        if (flen > 0 && (filename_inzip[flen - 1] == '/' ||
                         filename_inzip[flen - 1] == '\\')) {
            // directory entry
        } else {
            if (unzOpenCurrentFilePassword(uf, nullptr) == UNZ_OK) {
                char* buf = (char*)std::malloc((size_t)file_info.uncompressed_size);
                if (buf) {
                    int rd = unzReadCurrentFile(uf, buf,
                                                (unsigned int)file_info.uncompressed_size);
                    if (rd == (int)file_info.uncompressed_size) {
                        file_data_t fdata{buf, (int)file_info.uncompressed_size};
                        m_flist.insert({filename_inzip, fdata});
                    } else {
                        std::free(buf);
                    }
                }
                unzCloseCurrentFile(uf);
            }
        }

        if (i + 1 < gi.number_entry) {
            err = unzGoToNextFile(uf);
            if (err != UNZ_OK) break;
        }
        if (m_bForceKill.load()) { err = UNZ_ERRNO; break; }
    }
    unzClose(uf);
    if (err != UNZ_OK && err != UNZ_END_OF_LIST_OF_FILE) {
        FreeFilelist();
        return FALSE;
    }
    return TRUE;
}

BOOL EpubBook::ParserOcf(epub_t& epub) {
    auto itor = m_flist.find(epub.ocf);
    if (itor == m_flist.end()) return FALSE;

    xmlDocPtr doc = xmlReadMemory((const char*)itor->second.data,
                                  itor->second.size, nullptr, nullptr,
                                  XML_PARSE_RECOVER | XML_PARSE_NOBLANKS);
    if (!doc) return FALSE;
    if (m_bForceKill.load()) { xmlFreeDoc(doc); return FALSE; }

    xmlXPathContextPtr xpathctx = xmlXPathNewContext(doc);
    if (!xpathctx) { xmlFreeDoc(doc); return FALSE; }

    xmlXPathObjectPtr xpathobj = xmlXPathEvalExpression(
        BAD_CAST "//*[local-name()='rootfile']/@full-path", xpathctx);

    BOOL ret = FALSE;
    if (xpathobj && !xmlXPathNodeSetIsEmpty(xpathobj->nodesetval)) {
        xmlNodeSetPtr nodeset = xpathobj->nodesetval;
        for (int i = 0; i < nodeset->nodeNr; ++i) {
            xmlChar* kw = xmlNodeGetContent(nodeset->nodeTab[i]);
            if (kw && kw[0]) {
                epub.opf = (const char*)kw;
                auto slash = epub.opf.rfind('/');
                if (slash != std::string::npos) epub.path = epub.opf.substr(0, slash + 1);
                ret = TRUE;
                xmlFree(kw);
                break;
            }
            if (kw) xmlFree(kw);
        }
    }
    if (xpathobj) xmlXPathFreeObject(xpathobj);
    xmlXPathFreeContext(xpathctx);
    xmlFreeDoc(doc);
    return ret;
}

BOOL EpubBook::ParserOpf(epub_t& epub) {
    auto itor = m_flist.find(epub.opf);
    if (itor == m_flist.end()) return FALSE;

    xmlDocPtr doc = xmlReadMemory((const char*)itor->second.data,
                                  itor->second.size, nullptr, nullptr,
                                  XML_PARSE_RECOVER | XML_PARSE_NOBLANKS);
    if (!doc) return FALSE;
    if (m_bForceKill.load()) { xmlFreeDoc(doc); return FALSE; }

    xmlXPathContextPtr xpathctx = xmlXPathNewContext(doc);
    if (!xpathctx) { xmlFreeDoc(doc); return FALSE; }

    BOOL ret = FALSE;
    char buff[1024];

    // manifest
    xmlXPathObjectPtr xpathobj = xmlXPathEvalExpression(
        BAD_CAST "//*[local-name()='item']/@*[name()='id' or name()='href' or name()='media-type']",
        xpathctx);
    if (!xpathobj || xmlXPathNodeSetIsEmpty(xpathobj->nodesetval)) goto end;

    {
        xmlNodeSetPtr nodeset = xpathobj->nodesetval;
        for (int i = 0; i < nodeset->nodeNr; /* i++ */) {
            manifest_t* item = new manifest_t;
            for (int j = 0; j < 3 && i < nodeset->nodeNr; ++j, ++i) {
                xmlChar* kw = xmlNodeGetContent(nodeset->nodeTab[i]);
                if (kw && kw[0]) {
                    if (xmlStrcmp(nodeset->nodeTab[i]->name, (const xmlChar*)"id") == 0) {
                        item->id = (const char*)kw;
                    } else if (xmlStrcmp(nodeset->nodeTab[i]->name, (const xmlChar*)"href") == 0) {
                        url_decode((const char*)kw, buff);
                        item->href = buff;
                    } else if (xmlStrcmp(nodeset->nodeTab[i]->name, (const xmlChar*)"media-type") == 0) {
                        item->media_type = (const char*)kw;
                    }
                }
                if (kw) xmlFree(kw);
                if (m_bForceKill.load()) { delete item; goto end; }
            }
            if (!item->id.empty() && !item->href.empty() && !item->media_type.empty()) {
                epub.manifests.insert({item->id, item});
            } else {
                delete item;
                goto end;
            }
        }
        if (epub.manifests.empty()) goto end;
    }

    xmlXPathFreeObject(xpathobj);
    xpathobj = xmlXPathEvalExpression(
        BAD_CAST "//*[local-name()='itemref']/@idref", xpathctx);
    if (!xpathobj || xmlXPathNodeSetIsEmpty(xpathobj->nodesetval)) goto end;

    {
        xmlNodeSetPtr nodeset = xpathobj->nodesetval;
        for (int i = 0; i < nodeset->nodeNr; ++i) {
            xmlChar* kw = xmlNodeGetContent(nodeset->nodeTab[i]);
            if (kw && kw[0]) {
                if (epub.manifests.find((const char*)kw) == epub.manifests.end()) {
                    xmlFree(kw); goto end;
                }
                epub.spines.push_back((const char*)kw);
            }
            if (kw) xmlFree(kw);
            if (m_bForceKill.load()) goto end;
        }
        if (epub.spines.empty()) goto end;
    }
    ret = TRUE;
    if (m_bForceKill.load()) { ret = FALSE; goto end; }

    // ncx (optional)
    xmlXPathFreeObject(xpathobj);
    xpathobj = xmlXPathEvalExpression(
        BAD_CAST "//*[local-name()='spine']/@toc", xpathctx);
    if (xpathobj && !xmlXPathNodeSetIsEmpty(xpathobj->nodesetval)) {
        xmlNodeSetPtr nodeset = xpathobj->nodesetval;
        for (int i = 0; i < nodeset->nodeNr; ++i) {
            xmlChar* kw = xmlNodeGetContent(nodeset->nodeTab[i]);
            if (kw && kw[0]) {
                auto it = epub.manifests.find((const char*)kw);
                if (it != epub.manifests.end()) epub.ncx = it->second->href;
                xmlFree(kw);
                break;
            }
            if (kw) xmlFree(kw);
        }
    }

end:
    if (xpathobj) xmlXPathFreeObject(xpathobj);
    xmlXPathFreeContext(xpathctx);
    xmlFreeDoc(doc);
    return ret;
}

BOOL EpubBook::ParserNcx(epub_t& epub) {
    if (epub.ncx.empty()) return TRUE;
    auto itor = m_flist.find(epub.path + epub.ncx);
    if (itor == m_flist.end()) return FALSE;

    xmlDocPtr doc = xmlReadMemory((const char*)itor->second.data,
                                  itor->second.size, nullptr, nullptr,
                                  XML_PARSE_RECOVER | XML_PARSE_NOBLANKS);
    if (!doc) return FALSE;
    if (m_bForceKill.load()) { xmlFreeDoc(doc); return FALSE; }

    xmlXPathContextPtr xpathctx = xmlXPathNewContext(doc);
    if (!xpathctx) { xmlFreeDoc(doc); return FALSE; }

    xmlXPathObjectPtr xpathobj = xmlXPathEvalExpression(
        BAD_CAST "//*[local-name()='navPoint']", xpathctx);
    BOOL ret = FALSE;
    if (xpathobj && !xmlXPathNodeSetIsEmpty(xpathobj->nodesetval)) {
        xmlNodeSetPtr nodeset = xpathobj->nodesetval;
        char buff[1024];
        for (int i = 0; i < nodeset->nodeNr; ++i) {
            xmlNodePtr node = nodeset->nodeTab[i];
            xmlChar* id    = xmlGetProp(node, BAD_CAST "id");
            xmlChar* order = xmlGetProp(node, BAD_CAST "playOrder");
            xmlChar* text  = nullptr;
            xmlChar* src   = nullptr;
            int flag = 0;
            xmlNodePtr child = node->children;
            while (child) {
                if (xmlStrcasecmp(child->name, BAD_CAST "content") == 0) {
                    src = xmlGetProp(child, BAD_CAST "src");
                    ++flag;
                }
                if (xmlStrcasecmp(child->name, BAD_CAST "navLabel") == 0) {
                    text = xmlNodeGetContent(child->children);
                    ++flag;
                }
                if (flag >= 2) break;
                child = child->next;
            }
            navpoint_t* np = new navpoint_t;
            if (id) np->id = (const char*)id;
            if (order) np->order = std::atoi((const char*)order);
            if (text) np->text = (const char*)text;
            if (src) {
                url_decode((const char*)src, buff);
                np->src = buff;
            }
            epub.navpoints.insert({np->src, np});
            if (id) xmlFree(id);
            if (order) xmlFree(order);
            if (text) xmlFree(text);
            if (src) xmlFree(src);
            if (m_bForceKill.load()) break;
        }
        ret = !epub.navpoints.empty();
    }
    if (xpathobj) xmlXPathFreeObject(xpathobj);
    xmlXPathFreeContext(xpathctx);
    xmlFreeDoc(doc);
    return ret;
}

BOOL EpubBook::ParserOps(file_data_t* fdata, wchar_t** text, int* len,
                         wchar_t** title, int* tlen, BOOL parsertitle) {
    xmlKeepBlanksDefault(0);
    xmlDocPtr doc = htmlReadMemory((const char*)fdata->data, fdata->size,
                                   nullptr, nullptr,
                                   XML_PARSE_RECOVER | XML_PARSE_NOBLANKS);
    if (!doc) return FALSE;
    if (m_bForceKill.load()) { xmlFreeDoc(doc); return FALSE; }

    xmlChar* fmt_str = nullptr;
    int size = 0;
    htmlDocDumpMemoryFormat(doc, &fmt_str, &size, 1);
    xmlFreeDoc(doc);
    if (!fmt_str || size <= 0) {
        if (fmt_str) xmlFree(fmt_str);
        return FALSE;
    }
    xmlKeepBlanksDefault(1);
    doc = xmlReadMemory((const char*)fmt_str, size, nullptr, nullptr,
                        XML_PARSE_RECOVER);
    xmlFree(fmt_str);
    if (!doc) return FALSE;

    xmlXPathContextPtr xpathctx = xmlXPathNewContext(doc);
    if (!xpathctx) { xmlFreeDoc(doc); return FALSE; }
    if (m_bForceKill.load()) { xmlXPathFreeContext(xpathctx); xmlFreeDoc(doc); return FALSE; }

    BOOL ret = FALSE;
    xmlXPathObjectPtr xpathobj = nullptr;

    if (parsertitle) {
        xpathobj = xmlXPathEvalExpression(
            BAD_CAST "//*[local-name()='title']", xpathctx);
        if (xpathobj && !xmlXPathNodeSetIsEmpty(xpathobj->nodesetval)) {
            xmlNodeSetPtr ns = xpathobj->nodesetval;
            for (int i = 0; i < ns->nodeNr; ++i) {
                xmlChar* v = xmlNodeGetContent(ns->nodeTab[i]);
                if (v) {
                    DecodeText((const char*)v, (int)std::strlen((const char*)v),
                               title, tlen);
                    xmlFree(v);
                }
                break;
            }
        }
    }
    if (m_bForceKill.load()) goto end;

    if (xpathobj) xmlXPathFreeObject(xpathobj);
    xpathobj = xmlXPathEvalExpression(
        BAD_CAST "//*[local-name()='body']", xpathctx);
    if (xpathobj && !xmlXPathNodeSetIsEmpty(xpathobj->nodesetval)) {
        xmlNodeSetPtr ns = xpathobj->nodesetval;
        for (int i = 0; i < ns->nodeNr; ++i) {
            xmlChar* v = xmlNodeGetContent(ns->nodeTab[i]);
            if (v) {
                ret = DecodeText((const char*)v,
                                 (int)std::strlen((const char*)v), text, len);
                xmlFree(v);
            }
            break;
        }
    }

end:
    if (xpathobj) xmlXPathFreeObject(xpathobj);
    xmlXPathFreeContext(xpathctx);
    xmlFreeDoc(doc);
    return ret;
}

BOOL EpubBook::ParserChapters(epub_t& epub) {
    struct buf_t { wchar_t* text; int len; };
    std::vector<buf_t> buffer;
    m_Length = HasCover() ? 1 : 0;
    int index = 0;

    for (auto& spine : epub.spines) {
        if (m_bForceKill.load()) goto fail;
        auto itm = epub.manifests.find(spine);
        if (itm == epub.manifests.end()) continue;
        std::string filename = epub.path + itm->second->href;
        auto itf = m_flist.find(filename);
        auto itn = epub.navpoints.find(itm->second->href);
        if (itf == m_flist.end()) continue;

        wchar_t* text  = nullptr;
        wchar_t* title = nullptr;
        int len = 0, tlen = 0;
        if (ParserOps(&itf->second, &text, &len, &title, &tlen,
                      itn == epub.navpoints.end())) {
            if (len > 0) {
                buffer.push_back({text, len});
                chapter_item_t chapter;
                chapter.index = m_Length;
                m_Length += len;
                if (itn != epub.navpoints.end()) {
                    if (title) { std::free(title); title = nullptr; }
                    DecodeText(itn->second->text.c_str(),
                               (int)itn->second->text.size(), &title, &tlen);
                }
                if (title) {
                    chapter.title = title;
                    chapter.title_len = tlen;
                    std::free(title);
                }
                if (!chapter.title.empty()) m_Chapters.push_back(chapter);
                ++index;
            } else if (text) {
                std::free(text);
                if (title) std::free(title);
            }
        } else {
            if (text) std::free(text);
            if (title) std::free(title);
        }
    }

    if (index > 0) {
        int off = 0;
        m_Text = (wchar_t*)std::malloc(sizeof(wchar_t) * (size_t)(m_Length + 1));
        if (HasCover()) { m_Text[0] = 0x0A; off = 1; }
        for (auto& b : buffer) {
            std::memcpy(m_Text + off, b.text, sizeof(wchar_t) * (size_t)b.len);
            off += b.len;
            std::free(b.text);
        }
        m_Text[m_Length] = 0;
    }
    return TRUE;

fail:
    for (auto& b : buffer) std::free(b.text);
    return FALSE;
}

BOOL EpubBook::ParserCover(epub_t& epub) {
    m_CoverData.clear();
    m_CoverMediaType.clear();
    char image_fname[1024] = {0};
    const char* cover_fname = nullptr;

    if (!epub.navpoints.empty()) {
        for (auto& kv : epub.navpoints) {
            navpoint_t* np = kv.second;
            if (np->order <= 1 &&
                (strcasestr(np->id.c_str(), "cover") ||
                 strcasestr(np->src.c_str(), "cover"))) {
                for (auto& mkv : epub.manifests) {
                    if (np->src == mkv.second->href) {
                        cover_fname = mkv.second->href.c_str();
                        goto found;
                    }
                }
                break;
            }
        }
    }
    if (!epub.spines.empty() && strcasestr(epub.spines.front().c_str(), "cover")) {
        auto it = epub.manifests.find(epub.spines.front());
        if (it != epub.manifests.end()) {
            cover_fname = it->second->href.c_str();
            goto found;
        }
    }
    for (auto& mkv : epub.manifests) {
        if (strcasestr(mkv.first.c_str(), "cover") &&
            strcasestr(mkv.second->media_type.c_str(), "image/")) {
            std::strncpy(image_fname, mkv.second->href.c_str(),
                         sizeof(image_fname) - 1);
            goto complete;
        }
    }

found:
    if (cover_fname) {
        auto itf = m_flist.find(epub.path + cover_fname);
        if (itf != m_flist.end()) {
            xmlDocPtr doc = xmlReadMemory((const char*)itf->second.data,
                                          itf->second.size, nullptr, nullptr,
                                          XML_PARSE_RECOVER | XML_PARSE_NOBLANKS);
            if (doc) {
                xmlXPathContextPtr ctx = xmlXPathNewContext(doc);
                if (ctx) {
                    xmlXPathObjectPtr obj = xmlXPathEvalExpression(
                        BAD_CAST "//*[local-name()='img']", ctx);
                    if (!obj || xmlXPathNodeSetIsEmpty(obj->nodesetval)) {
                        if (obj) xmlXPathFreeObject(obj);
                        obj = xmlXPathEvalExpression(
                            BAD_CAST "//*[local-name()='image']", ctx);
                    }
                    if (obj && !xmlXPathNodeSetIsEmpty(obj->nodesetval)) {
                        xmlNodeSetPtr ns = obj->nodesetval;
                        for (int i = 0; i < ns->nodeNr; ++i) {
                            xmlNodePtr n = ns->nodeTab[i];
                            xmlChar* src  = xmlGetProp(n, BAD_CAST "src");
                            xmlChar* href = xmlGetProp(n, BAD_CAST "href");
                            const xmlChar* pick = src ? src : href;
                            if (pick) {
                                url_decode((const char*)pick, image_fname);
                                while (std::strstr(image_fname, "../") == image_fname) {
                                    std::memmove(image_fname, image_fname + 3,
                                                 std::strlen(image_fname) - 2);
                                }
                            }
                            if (src) xmlFree(src);
                            if (href) xmlFree(href);
                            break;
                        }
                    }
                    if (obj) xmlXPathFreeObject(obj);
                    xmlXPathFreeContext(ctx);
                }
                xmlFreeDoc(doc);
            }
        }
    }

complete:
    if (image_fname[0]) {
        auto itf = m_flist.find(epub.path + image_fname);
        if (itf != m_flist.end()) {
            m_CoverData.assign(
                (uint8_t*)itf->second.data,
                (uint8_t*)itf->second.data + itf->second.size);
            // try to find the media-type from manifest
            for (auto& mkv : epub.manifests) {
                if (mkv.second->href == image_fname) {
                    m_CoverMediaType = mkv.second->media_type;
                    break;
                }
            }
        }
    }
    return TRUE;
}

BOOL EpubBook::ParserBook(void) {
    epub_t epub;
    epub.ocf = "META-INF/container.xml";

    BOOL ret = FALSE;
    if (!UnzipBook()) goto end;
    if (!ParserOcf(epub)) goto end;
    if (!ParserOpf(epub)) goto end;
    if (!ParserNcx(epub)) goto end;
    ParserCover(epub);
    if (!ParserChapters(epub)) goto end;
    ret = TRUE;

end:
    for (auto& kv : epub.manifests) delete kv.second;
    epub.manifests.clear();
    for (auto& kv : epub.navpoints) delete kv.second;
    epub.navpoints.clear();
    epub.spines.clear();
    FreeFilelist();
    if (!ret) {
        m_CoverData.clear();
        m_CoverMediaType.clear();
        CloseBook();
    }
    return ret;
}
