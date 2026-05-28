#include "doctest/doctest.h"
#include "reader/html_parser.h"

#include <string>
#include <vector>

TEST_CASE("HtmlParser extracts XPath results") {
    const char html[] =
        "<html><body>"
        "<div class='title'>Chapter 1</div>"
        "<div class='title'>Chapter 2</div>"
        "<p>some body text</p>"
        "</body></html>";

    std::vector<std::string> titles;
    int stop = 0;
    int rc = HtmlParser::Instance()->HtmlParseByXpath(
        html, (int)sizeof(html) - 1,
        "//div[@class='title']", titles, &stop, FALSE);

    CHECK(rc == 0);
    REQUIRE(titles.size() == 2);
    CHECK(titles[0] == "Chapter 1");
    CHECK(titles[1] == "Chapter 2");
}

TEST_CASE("HtmlParser multi-step interface") {
    const char html[] = "<html><body><a href='ch1.html'>One</a><a href='ch2.html'>Two</a></body></html>";
    int stop = 0;
    void* doc = nullptr;
    void* ctx = nullptr;

    REQUIRE(HtmlParser::Instance()->HtmlParseBegin(html, (int)sizeof(html) - 1, &doc, &ctx, &stop) == 0);

    std::vector<std::string> hrefs;
    HtmlParser::Instance()->HtmlParseByXpath(doc, ctx, "//a/@href", hrefs, &stop, FALSE);
    CHECK(hrefs.size() == 2);
    CHECK(hrefs[0] == "ch1.html");
    CHECK(hrefs[1] == "ch2.html");

    std::vector<std::string> texts;
    HtmlParser::Instance()->HtmlParseByXpath(doc, ctx, "//a", texts, &stop, FALSE);
    CHECK(texts.size() == 2);

    HtmlParser::Instance()->HtmlParseEnd(doc, ctx);
}
