// ReaderCore: cross-platform port of libhttps's https.h.
// On Windows we'd still link the real libhttps; on macOS the implementation
// lives in platform/macos/https_nsurl.mm (NSURLSession-backed).

#pragma once

#include "reader/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

// All Win32 ABI decorations removed (__declspec/__stdcall).

typedef void* req_handler_t;
typedef unsigned int (*progress_cb)(void* param, double dltotal, double dlnow,
                                    double ultotal, double ulnow);
typedef unsigned int (*write_data_cb)(void* data, unsigned int size,
                                      unsigned int nmemb, void* stream);
typedef struct request_result_t request_result_t;
typedef unsigned int (*complete_cb)(request_result_t* result);
typedef void (*logger_print)(char const* const format, ...);

typedef enum request_method_t {
    HTTP_GET,
    HTTP_POST,
    HTTP_HEAD
} request_method_t;

typedef enum HTTPS_errno_t {
    HTTPS_succ = 0,
    HTTPS_fail = -1,
    HTTPS_comp = -2,
    HTTPS_clos = -3,
    HTTPS_nonb = -4,
    HTTPS_nofe = -5
} HTTPS_errno_t;

typedef struct http_header_t {
    char* name;
    char* value;
    struct http_header_t* next;
} http_header_t;

typedef struct request_t {
    request_method_t method;
    char* url;
    char* content;           // POST body
    int   content_length;
    char* extraheader;
    write_data_cb writer;
    void* stream;
    progress_cb progresser;
    void* param;
    complete_cb completer;
    void* param1;
    void* param2;
} request_t;

struct request_result_t {
    int errno_;
    int cancel;
    void* param1;
    void* param2;
    http_header_t* header;
    int status_code;
    char* status_desc;
    char* body;
    int bodylen;
    request_t* req;
    req_handler_t handler;
};

typedef struct http_proxy_t {
    int   enable;
    char* addr;
    char* user;
    char* pass;
    int   port;
} http_proxy_t;

typedef enum http_charset_t {
    HTTPS_utf_8,
    HTTPS_gbk
} http_charset_t;

int  hapi_init(void);
int  hapi_uninit(void);
int  hapi_set_proxy(const http_proxy_t* proxy);
int  hapi_set_cert(int enable, const char* filename);
int  hapi_enable_internal_redirect(int enable);
int  hapi_enable_internal_gzip_inflate(int enable);
int  hapi_enable_internal_cache_cookie(int able);
int  hapi_set_logger(logger_print logger);

req_handler_t hapi_request(const request_t* req);
int           hapi_cancel(req_handler_t handler);
request_t*    hapi_get_request_info(req_handler_t handler);

int  hapi_buffer_free(char* dst);
int  hapi_url_encode(const char* src, char** dst);
int  hapi_url_decode(const char* src, char** dst);
int  hapi_base64_encode(const char* src, int slen, char* dst, int* dlen);
int  hapi_base64_decode(const char* src, int slen, char* dst, int* dlen);

int  hapi_gzip_inflate(const unsigned char* src, int srclen,
                       unsigned char** dst, int* dstlen);
int  hapi_is_gzip(const http_header_t* header);
const char*   hapi_get_location(const http_header_t* header);
http_charset_t hapi_get_charset(const http_header_t* header);

#ifdef __cplusplus
}  // extern "C"
#endif
