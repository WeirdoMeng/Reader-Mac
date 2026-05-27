// macOS implementation of reader's https.h, backed by NSURLSession.
// Replaces the libhttps + wolfssl stack on the Windows version with native
// Foundation networking — TLS, cookies, redirects, gzip all handled by the
// system.

#import <Foundation/Foundation.h>
#import <zlib.h>

#include "reader/https.h"
#include "reader/utils.h"

#include <atomic>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>

// -------- module-private state --------
namespace {

struct GlobalState {
    NSURLSession*  session       = nil;
    NSURLSession*  noredirect    = nil;
    http_proxy_t   proxy         = {0, nullptr, nullptr, nullptr, 0};
    bool           internal_redirect      = true;
    bool           internal_gzip_inflate  = true;
    bool           internal_cache_cookie  = true;
    logger_print   logger        = nullptr;

};

GlobalState& state() {
    static GlobalState s;
    return s;
}

void log_msg(const char* fmt, ...) {
    auto& s = state();
    if (!s.logger) return;
    char buf[512];
    va_list ap; va_start(ap, fmt);
    std::vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    s.logger("%s", buf);
}

// Build a header chain from NSDictionary.
http_header_t* build_header_chain(NSDictionary* fields) {
    http_header_t* head = nullptr;
    http_header_t* tail = nullptr;
    for (NSString* k in fields) {
        NSString* v = fields[k];
        http_header_t* h = (http_header_t*)std::calloc(1, sizeof(http_header_t));
        h->name  = strdup(k.UTF8String);
        h->value = strdup(v.UTF8String);
        if (!head) head = h; else tail->next = h;
        tail = h;
    }
    return head;
}

void free_header_chain(http_header_t* h) {
    while (h) {
        http_header_t* n = h->next;
        std::free(h->name);
        std::free(h->value);
        std::free(h);
        h = n;
    }
}

// Lowercase ASCII compare (for header lookup).
const char* find_header(const http_header_t* h, const char* name) {
    while (h) {
        if (h->name && strcasecmp(h->name, name) == 0) return h->value;
        h = h->next;
    }
    return nullptr;
}

}  // anonymous namespace

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

extern "C" int hapi_init(void) {
    @autoreleasepool {
        auto& s = state();
        NSURLSessionConfiguration* cfg =
            [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.HTTPMaximumConnectionsPerHost = 6;
        cfg.timeoutIntervalForRequest = 30.0;
        cfg.timeoutIntervalForResource = 60.0;
        if (s.session) [s.session invalidateAndCancel];
        s.session = [NSURLSession sessionWithConfiguration:cfg];

        NSURLSessionConfiguration* nrCfg =
            [NSURLSessionConfiguration defaultSessionConfiguration];
        nrCfg.HTTPMaximumConnectionsPerHost = 6;
        nrCfg.timeoutIntervalForRequest = 30.0;
        nrCfg.timeoutIntervalForResource = 60.0;
        if (s.noredirect) [s.noredirect invalidateAndCancel];
        s.noredirect = [NSURLSession sessionWithConfiguration:nrCfg];
        return HTTPS_succ;
    }
}

extern "C" int hapi_uninit(void) {
    @autoreleasepool {
        auto& s = state();
        if (s.session) [s.session invalidateAndCancel];
        if (s.noredirect) [s.noredirect invalidateAndCancel];
        s.session = nil;
        s.noredirect = nil;
        return HTTPS_succ;
    }
}

extern "C" int hapi_set_proxy(const http_proxy_t* p) {
    auto& s = state();
    if (s.proxy.addr) std::free(s.proxy.addr);
    if (s.proxy.user) std::free(s.proxy.user);
    if (s.proxy.pass) std::free(s.proxy.pass);
    s.proxy = {0, nullptr, nullptr, nullptr, 0};
    if (p) {
        s.proxy.enable = p->enable;
        s.proxy.port   = p->port;
        if (p->addr) s.proxy.addr = strdup(p->addr);
        if (p->user) s.proxy.user = strdup(p->user);
        if (p->pass) s.proxy.pass = strdup(p->pass);
        // TODO: rebuild session with NSURLSessionConfiguration.connectionProxyDictionary
        // if proxy.enable. Not used for first MVP.
    }
    return HTTPS_succ;
}

extern "C" int hapi_set_cert(int /*enable*/, const char* /*filename*/) {
    return HTTPS_succ;  // NSURLSession uses system trust by default.
}
extern "C" int hapi_enable_internal_redirect(int e) {
    state().internal_redirect = e != 0;
    return HTTPS_succ;
}
extern "C" int hapi_enable_internal_gzip_inflate(int e) {
    state().internal_gzip_inflate = e != 0;
    return HTTPS_succ;
}
extern "C" int hapi_enable_internal_cache_cookie(int e) {
    state().internal_cache_cookie = e != 0;
    return HTTPS_succ;
}
extern "C" int hapi_set_logger(logger_print l) {
    state().logger = l;
    return HTTPS_succ;
}

// ---------------------------------------------------------------------------
// Request / cancel
// ---------------------------------------------------------------------------

// Parse "Key: Value\r\nKey2: Value2\r\n" extra-headers into NSURLRequest fields.
static void apply_extra_headers(NSMutableURLRequest* req, const char* extra) {
    if (!extra || !*extra) return;
    const char* p = extra;
    while (*p) {
        const char* line_end = std::strstr(p, "\r\n");
        size_t len = line_end ? (size_t)(line_end - p) : std::strlen(p);
        const char* colon = (const char*)std::memchr(p, ':', len);
        if (colon && colon > p) {
            size_t klen = (size_t)(colon - p);
            const char* v = colon + 1;
            while (v < p + len && *v == ' ') ++v;
            size_t vlen = (size_t)(p + len - v);
            NSString* k = [[NSString alloc] initWithBytes:p length:klen encoding:NSUTF8StringEncoding];
            NSString* val = [[NSString alloc] initWithBytes:v length:vlen encoding:NSUTF8StringEncoding];
            [req setValue:val forHTTPHeaderField:k];
        }
        if (!line_end) break;
        p = line_end + 2;
    }
}

extern "C" req_handler_t hapi_request(const request_t* req) {
    if (!req || !req->url) return nullptr;
    auto& s = state();
    if (!s.session) hapi_init();

    @autoreleasepool {
        NSString* urlStr = [NSString stringWithUTF8String:req->url];
        NSURL* url = [NSURL URLWithString:urlStr];
        if (!url) return nullptr;

        NSMutableURLRequest* nreq = [NSMutableURLRequest requestWithURL:url];
        nreq.timeoutInterval = 30.0;
        switch (req->method) {
            case HTTP_GET:  nreq.HTTPMethod = @"GET";  break;
            case HTTP_POST: nreq.HTTPMethod = @"POST"; break;
            case HTTP_HEAD: nreq.HTTPMethod = @"HEAD"; break;
        }
        if (req->method == HTTP_POST && req->content && req->content_length > 0) {
            nreq.HTTPBody = [NSData dataWithBytes:req->content
                                            length:(NSUInteger)req->content_length];
        }
        apply_extra_headers(nreq, req->extraheader);

        // Choose session based on redirect policy.
        NSURLSession* sess = s.internal_redirect ? s.session : s.noredirect;

        // Capture only PODs/pointers into the block to avoid retains on req_t.
        request_t* req_copy = (request_t*)std::malloc(sizeof(request_t));
        std::memcpy(req_copy, req, sizeof(request_t));

        NSURLSessionDataTask* task =
            [sess dataTaskWithRequest:nreq
                    completionHandler:^(NSData* data, NSURLResponse* resp, NSError* err) {
                request_result_t result;
                std::memset(&result, 0, sizeof(result));
                result.param1  = req_copy->param1;
                result.param2  = req_copy->param2;
                result.req     = req_copy;
                result.handler = nullptr;

                if (err) {
                    log_msg("hapi_request error: %s", err.localizedDescription.UTF8String);
                    if (err.code == NSURLErrorCancelled) {
                        result.errno_ = HTTPS_clos;
                        result.cancel = 1;
                    } else {
                        result.errno_ = HTTPS_fail;
                    }
                } else if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
                    NSHTTPURLResponse* hresp = (NSHTTPURLResponse*)resp;
                    result.status_code = (int)hresp.statusCode;
                    result.header = build_header_chain(hresp.allHeaderFields);
                    NSString* desc =
                        [NSHTTPURLResponse localizedStringForStatusCode:hresp.statusCode];
                    if (desc) result.status_desc = strdup(desc.UTF8String);
                    result.errno_ = HTTPS_succ;

                    if (data && data.length > 0) {
                        result.bodylen = (int)data.length;
                        result.body    = (char*)std::malloc((size_t)result.bodylen + 1);
                        std::memcpy(result.body, data.bytes, (size_t)result.bodylen);
                        result.body[result.bodylen] = 0;
                    }
                } else {
                    result.errno_ = HTTPS_fail;
                }

                if (req_copy->completer) req_copy->completer(&result);

                // cleanup
                free_header_chain(result.header);
                if (result.status_desc) std::free(result.status_desc);
                if (result.body) std::free(result.body);
                std::free(req_copy);
            }];

        [task resume];
        return (__bridge_retained void*)task;
    }
}

extern "C" int hapi_cancel(req_handler_t handler) {
    if (!handler) return HTTPS_fail;
    @autoreleasepool {
        NSURLSessionTask* task = (__bridge_transfer NSURLSessionTask*)handler;
        [task cancel];
    }
    return HTTPS_succ;
}

extern "C" request_t* hapi_get_request_info(req_handler_t /*handler*/) {
    return nullptr;  // Not used by OnlineBook in the original codebase path
                     // we care about; revisit if needed.
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

extern "C" int hapi_buffer_free(char* dst) {
    if (dst) std::free(dst);
    return HTTPS_succ;
}

extern "C" int hapi_url_encode(const char* src, char** dst) {
    if (!src || !dst) return HTTPS_fail;
    NSString* s = [NSString stringWithUTF8String:src];
    NSCharacterSet* set = [NSCharacterSet URLQueryAllowedCharacterSet];
    NSString* enc = [s stringByAddingPercentEncodingWithAllowedCharacters:set];
    if (!enc) return HTTPS_fail;
    *dst = strdup(enc.UTF8String);
    return HTTPS_succ;
}

extern "C" int hapi_url_decode(const char* src, char** dst) {
    if (!src || !dst) return HTTPS_fail;
    NSString* s = [NSString stringWithUTF8String:src];
    NSString* dec = [s stringByRemovingPercentEncoding];
    if (!dec) return HTTPS_fail;
    *dst = strdup(dec.UTF8String);
    return HTTPS_succ;
}

extern "C" int hapi_base64_encode(const char* src, int slen, char* dst, int* dlen) {
    NSData* d = [NSData dataWithBytes:src length:(NSUInteger)slen];
    NSString* b = [d base64EncodedStringWithOptions:0];
    int len = (int)b.length;
    if (dlen) *dlen = len;
    if (dst) std::memcpy(dst, b.UTF8String, (size_t)len);
    return HTTPS_succ;
}

extern "C" int hapi_base64_decode(const char* src, int slen, char* dst, int* dlen) {
    NSString* s = [[NSString alloc] initWithBytes:src length:(NSUInteger)slen
                                          encoding:NSUTF8StringEncoding];
    NSData* d = [[NSData alloc] initWithBase64EncodedString:s options:0];
    if (!d) return HTTPS_fail;
    int len = (int)d.length;
    if (dlen) *dlen = len;
    if (dst) std::memcpy(dst, d.bytes, (size_t)len);
    return HTTPS_succ;
}

extern "C" int hapi_gzip_inflate(const unsigned char* src, int srclen,
                                 unsigned char** dst, int* dstlen) {
    if (!src || srclen <= 0 || !dst || !dstlen) return HTTPS_fail;
    // Use zlib's inflate with 32 + MAX_WBITS to autodetect gzip/zlib header.
    z_stream zs;
    std::memset(&zs, 0, sizeof(zs));
    if (inflateInit2(&zs, 32 + MAX_WBITS) != Z_OK) return HTTPS_fail;

    size_t cap = (size_t)srclen * 4 + 1024;
    unsigned char* buf = (unsigned char*)std::malloc(cap);
    if (!buf) { inflateEnd(&zs); return HTTPS_fail; }

    zs.next_in   = (Bytef*)src;
    zs.avail_in  = (uInt)srclen;
    zs.next_out  = buf;
    zs.avail_out = (uInt)cap;

    int rc = Z_OK;
    while (rc != Z_STREAM_END) {
        if (zs.avail_out == 0) {
            size_t old = cap;
            cap *= 2;
            unsigned char* nb = (unsigned char*)std::realloc(buf, cap);
            if (!nb) { std::free(buf); inflateEnd(&zs); return HTTPS_fail; }
            buf = nb;
            zs.next_out  = buf + old;
            zs.avail_out = (uInt)(cap - old);
        }
        rc = inflate(&zs, Z_NO_FLUSH);
        if (rc != Z_OK && rc != Z_STREAM_END) {
            std::free(buf);
            inflateEnd(&zs);
            return HTTPS_fail;
        }
    }
    *dstlen = (int)zs.total_out;
    *dst = buf;
    inflateEnd(&zs);
    return HTTPS_succ;
}

extern "C" int hapi_is_gzip(const http_header_t* h) {
    const char* enc = find_header(h, "Content-Encoding");
    if (!enc) return 0;
    return strcasestr(enc, "gzip") ? 1 : 0;
}

extern "C" const char* hapi_get_location(const http_header_t* h) {
    return find_header(h, "Location");
}

extern "C" http_charset_t hapi_get_charset(const http_header_t* h) {
    const char* ct = find_header(h, "Content-Type");
    if (ct && strcasestr(ct, "gbk")) return HTTPS_gbk;
    return HTTPS_utf_8;
}
