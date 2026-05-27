// ReaderCore: cross-platform MobiBook implementation.

#include "reader/mobi_book.h"
#include "reader/utils.h"

#include <libxml/HTMLparser.h>
#include <libxml/HTMLtree.h>
#include <libxml/xmlreader.h>
#include <libxml/xpath.h>

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

MobiBook::MobiBook() = default;
MobiBook::~MobiBook() {
    ForceKill();
    FreeFilelist();
}

book_type_t MobiBook::GetBookType(void) { return book_mobi; }
BOOL MobiBook::SaveBook(void) { return FALSE; }
BOOL MobiBook::UpdateChapters(int /*offset*/) { return FALSE; }
int  MobiBook::GetTextBeginIndex(void) { return HasCover() ? 1 : 0; }

void MobiBook::FreeFilelist(void) { m_flist.clear(); }

// Convert wchar_t path to UTF-8 for libmobi.
static std::string wpath_to_utf8(const wchar_t* p) {
    int n = 0;
    char* u = utf16_to_utf8(p, (int)std::wcslen(p), &n);
    std::string out;
    if (u) { out.assign(u, (size_t)n); free_buffer(u); }
    return out;
}

BOOL MobiBook::UnzipBook(MOBIRawml* rawml, MOBIData* /*m*/, mobi_t& mobi) {
    char partname[FILENAME_MAX];
    file_data_t fdata;
    FreeFilelist();

    if (rawml->markup) {
        for (MOBIPart* curr = rawml->markup; curr; curr = curr->next) {
            MOBIFileMeta fm = mobi_get_filemeta_by_type(curr->type);
            std::snprintf(partname, sizeof(partname),
                          "part%05zu.%s", curr->uid, fm.extension);
            fdata.data = curr->data;
            fdata.size = (int)curr->size;
            m_flist.insert({partname, fdata});
        }
    }
    if (rawml->flow) {
        MOBIPart* curr = rawml->flow ? rawml->flow->next : nullptr;
        while (curr) {
            MOBIFileMeta fm = mobi_get_filemeta_by_type(curr->type);
            std::snprintf(partname, sizeof(partname),
                          "flow%05zu.%s", curr->uid, fm.extension);
            fdata.data = curr->data;
            fdata.size = (int)curr->size;
            m_flist.insert({partname, fdata});
            curr = curr->next;
        }
    }
    if (rawml->resources) {
        for (MOBIPart* curr = rawml->resources; curr; curr = curr->next) {
            if (curr->size == 0) continue;
            MOBIFileMeta fm = mobi_get_filemeta_by_type(curr->type);
            int n = std::snprintf(partname, sizeof(partname),
                                  "resource%05zu.%s", curr->uid, fm.extension);
            if (n < 0 || (size_t)n >= sizeof(partname)) return FALSE;
            fdata.data = curr->data;
            fdata.size = (int)curr->size;
            m_flist.insert({partname, fdata});
            if (fm.type == T_OPF) mobi.opf = partname;
            if (fm.type == T_NCX) mobi.ncx = partname;
        }
    }
    return TRUE;
}

// Shared XML helpers (mostly identical to EpubBook's; deliberately copied here
// to avoid a refactor that's out of scope for this milestone).
BOOL MobiBook::ParserOpf(mobi_t& mobi) {
    auto itor = m_flist.find(mobi.opf);
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
                mobi.manifests.insert({item->id, item});
            } else {
                delete item;
                goto end;
            }
        }
        if (mobi.manifests.empty()) goto end;
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
                if (mobi.manifests.find((const char*)kw) == mobi.manifests.end()) {
                    xmlFree(kw); goto end;
                }
                mobi.spines.push_back((const char*)kw);
            }
            if (kw) xmlFree(kw);
            if (m_bForceKill.load()) goto end;
        }
        if (mobi.spines.empty()) goto end;
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
                auto it = mobi.manifests.find((const char*)kw);
                if (it != mobi.manifests.end()) mobi.ncx = it->second->href;
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

BOOL MobiBook::ParserNcx(mobi_t& mobi) {
    if (mobi.ncx.empty()) return TRUE;
    auto itor = m_flist.find(mobi.path + mobi.ncx);
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
    int nav_cnt = 0;
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
            mobi.navpoints.insert({np->src, np});
            ++nav_cnt;
            if (id) xmlFree(id);
            if (order) xmlFree(order);
            if (text) xmlFree(text);
            if (src) xmlFree(src);
            if (m_bForceKill.load()) break;
        }
        ret = !mobi.navpoints.empty();
        if (nav_cnt != (int)mobi.navpoints.size()) {
            // duplicate src — NCX unreliable, drop it
            mobi.navpoints.clear();
        }
    }
    if (xpathobj) xmlXPathFreeObject(xpathobj);
    xmlXPathFreeContext(xpathctx);
    xmlFreeDoc(doc);
    return ret;
}

BOOL MobiBook::ParserOps(file_data_t* fdata, wchar_t** text, int* len,
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
    if (!fmt_str || size <= 0) { if (fmt_str) xmlFree(fmt_str); return FALSE; }

    xmlKeepBlanksDefault(1);
    doc = xmlReadMemory((const char*)fmt_str, size, nullptr, nullptr,
                        XML_PARSE_RECOVER | XML_PARSE_HUGE);
    xmlFree(fmt_str);
    if (!doc) return FALSE;

    xmlXPathContextPtr xpathctx = xmlXPathNewContext(doc);
    if (!xpathctx) { xmlFreeDoc(doc); return FALSE; }

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
                    DecodeText((const char*)v,
                               (int)std::strlen((const char*)v), title, tlen);
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

BOOL MobiBook::ParserChapters(mobi_t& mobi) {
    struct buf_t { wchar_t* text; int len; };
    std::vector<buf_t> buffer;
    m_Length = HasCover() ? 1 : 0;
    int index = 0;

    for (auto& spine : mobi.spines) {
        if (m_bForceKill.load()) goto fail;
        auto itm = mobi.manifests.find(spine);
        if (itm == mobi.manifests.end()) continue;
        std::string filename = mobi.path + itm->second->href;
        auto itf = m_flist.find(filename);
        auto itn = mobi.navpoints.find(itm->second->href);
        if (itf == m_flist.end()) continue;

        wchar_t* text  = nullptr;
        wchar_t* title = nullptr;
        int len = 0, tlen = 0;
        if (ParserOps(&itf->second, &text, &len, &title, &tlen,
                      itn == mobi.navpoints.end())) {
            if (len > 0) {
                buffer.push_back({text, len});
                chapter_item_t chapter;
                chapter.index = m_Length;
                m_Length += len;
                if (itn != mobi.navpoints.end()) {
                    if (title) { std::free(title); title = nullptr; }
                    DecodeText(itn->second->text.c_str(),
                               (int)itn->second->text.size(), &title, &tlen);
                }
                if (tlen > 0 && title) {
                    chapter.title = title;
                    chapter.title_len = tlen;
                    m_Chapters.push_back(chapter);
                }
                if (title) std::free(title);
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

BOOL MobiBook::ParserCover(mobi_t& /*mobi*/, MOBIData* m) {
    m_CoverData.clear();
    m_CoverMediaType.clear();

    MOBIExthHeader* exth = mobi_get_exthrecord_by_tag(m, EXTH_COVEROFFSET);
    if (!exth) return FALSE;
    uint32_t offset = mobi_decode_exthvalue((unsigned char*)exth->data, exth->size);
    size_t first_resource = mobi_get_first_resource_record(m);
    size_t uid = first_resource + offset;
    MOBIPdbRecord* record = mobi_get_record_by_seqnumber(m, uid);
    if (!record || record->size < 4) return FALSE;

    const unsigned char jpg_magic[] = "\xff\xd8\xff";
    const unsigned char gif_magic[] = "\x47\x49\x46\x38";
    const unsigned char png_magic[] = "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a";
    const unsigned char bmp_magic[] = "\x42\x4d";

    if (std::memcmp(record->data, jpg_magic, 3) == 0) {
        m_CoverMediaType = "image/jpeg";
    } else if (std::memcmp(record->data, gif_magic, 4) == 0) {
        m_CoverMediaType = "image/gif";
    } else if (record->size >= 8 && std::memcmp(record->data, png_magic, 8) == 0) {
        m_CoverMediaType = "image/png";
    } else if (record->size >= 2 && std::memcmp(record->data, bmp_magic, 2) == 0) {
        m_CoverMediaType = "image/bmp";
    } else {
        m_CoverMediaType = "application/octet-stream";
    }

    m_CoverData.assign((const uint8_t*)record->data,
                       (const uint8_t*)record->data + record->size);
    return TRUE;
}

BOOL MobiBook::ParserBook(void) {
    BOOL ret = FALSE;
    mobi_t mobi;
    MOBIRawml* rawml = nullptr;

    MOBIData* m = mobi_init();
    if (!m) return FALSE;

    std::string upath = wpath_to_utf8(m_fileName);
    MOBI_RET mr = mobi_load_filename(m, upath.c_str());
    if (mr != MOBI_SUCCESS) { mobi_free(m); return FALSE; }

    rawml = mobi_init_rawml(m);
    if (!rawml) { mobi_free(m); return FALSE; }

    mr = mobi_parse_rawml(rawml, m);
    if (mr != MOBI_SUCCESS) { mobi_free_rawml(rawml); mobi_free(m); return FALSE; }

    if (!UnzipBook(rawml, m, mobi)) goto end;
    mobi.path = "";
    if (!ParserOpf(mobi)) goto end;
    if (!ParserNcx(mobi)) goto end;
    ParserCover(mobi, m);
    if (!ParserChapters(mobi)) goto end;
    ret = TRUE;

end:
    for (auto& kv : mobi.manifests) delete kv.second;
    mobi.manifests.clear();
    for (auto& kv : mobi.navpoints) delete kv.second;
    mobi.navpoints.clear();
    mobi.spines.clear();
    FreeFilelist();
    if (rawml) mobi_free_rawml(rawml);
    mobi_free(m);

    if (!ret) {
        m_CoverData.clear();
        m_CoverMediaType.clear();
        CloseBook();
    }
    return ret;
}
