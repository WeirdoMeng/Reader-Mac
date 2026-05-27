#include "doctest/doctest.h"
#include "reader/utils.h"

#include <cstdlib>
#include <cstring>
#include <string>

TEST_CASE("check_bom detects all standard BOMs") {
    CHECK(check_bom("\xEF\xBB\xBFhello", 8) == utf8);
    CHECK(check_bom("\xFF\xFEhi", 4) == utf16_le);
    CHECK(check_bom("\xFE\xFFhi", 4) == utf16_be);
    CHECK(check_bom("\xFF\xFE\x00\x00", 4) == utf32_le);
    CHECK(check_bom("\x00\x00\xFE\xFF", 4) == utf32_be);
    CHECK(check_bom("hello", 5) == Unknown);
}

TEST_CASE("is_ascii / is_utf8 classifiers") {
    const char ascii[] = "hello world";
    CHECK(is_ascii(ascii, sizeof(ascii) - 1) == 1);

    const char utf8_str[] = "\xE4\xBD\xA0\xE5\xA5\xBD";  // 你好
    CHECK(is_ascii(utf8_str, sizeof(utf8_str) - 1) == 0);
    CHECK(is_utf8(utf8_str, sizeof(utf8_str) - 1) == 1);

    // invalid utf8 continuation
    const char bad[] = "\xC0\x80";  // overlong NUL
    CHECK(is_utf8(bad, 2) == 0);
}

TEST_CASE("UTF-8 <-> wchar_t round trip") {
    const char utf8_str[] = "\xE4\xBD\xA0\xE5\xA5\xBD";  // 你好
    int wlen = 0;
    wchar_t* w = utf8_to_utf16(utf8_str, (int)strlen(utf8_str), &wlen);
    REQUIRE(w != nullptr);
    REQUIRE(wlen == 2);
    CHECK(w[0] == 0x4F60);  // 你
    CHECK(w[1] == 0x597D);  // 好

    int u8_len = 0;
    char* back = utf16_to_utf8(w, wlen, &u8_len);
    REQUIRE(back != nullptr);
    CHECK(u8_len == (int)strlen(utf8_str));
    CHECK(memcmp(back, utf8_str, u8_len) == 0);

    free_buffer(w);
    free_buffer(back);
}

TEST_CASE("base64 encode + decode round trip") {
    const char src[] = "Reader Mac port";
    char enc[64] = {0};
    int enc_len = 0;
    b64_encode(src, (int)strlen(src), enc, &enc_len);
    CHECK(std::string(enc, enc_len) == "UmVhZGVyIE1hYyBwb3J0");

    char dec[64] = {0};
    int dec_len = 0;
    b64_decode(enc, enc_len, dec, &dec_len);
    CHECK(dec_len == (int)strlen(src));
    CHECK(memcmp(dec, src, dec_len) == 0);
}

TEST_CASE("url_encode + url_decode") {
    char enc[256] = {0};
    int n = url_encode("hello world/中文", enc);
    CHECK(n > 0);
    // ' ' becomes '+', '/' percent-encoded, Chinese percent-encoded as UTF-8 bytes
    CHECK(std::string(enc).find("hello+world") != std::string::npos);
    // url_encode uses lowercase hex (matching upstream)
    CHECK(std::string(enc).find("%2f") != std::string::npos);

    char dec[256] = {0};
    url_decode(enc, dec);
    CHECK(std::string(dec) == "hello world/中文");
}

TEST_CASE("le_to_be flips byte pairs in place") {
    char buf[] = {0x11, 0x22, 0x33, 0x44};
    le_to_be(buf, 4);
    CHECK(buf[0] == 0x22);
    CHECK(buf[1] == 0x11);
    CHECK(buf[2] == 0x44);
    CHECK(buf[3] == 0x33);
}

TEST_CASE("memvcmp recognizes uniform fill") {
    unsigned char buf[16];
    std::memset(buf, 0x5A, sizeof(buf));
    CHECK(memvcmp(buf, 0x5A, sizeof(buf)) == 1);
    buf[7] = 0;
    CHECK(memvcmp(buf, 0x5A, sizeof(buf)) == 0);
}
