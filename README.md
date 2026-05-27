# Reader-Mac

将 [binbyu/Reader](https://github.com/binbyu/Reader) Windows 桌面阅读器移植为原生 macOS 应用。

- ✅ 原生 AppKit + Core Text，universal binary（arm64 + x86_64）
- ✅ 支持 .txt / .epub / .mobi / .azw / .azw3
- ✅ 章节自动识别 / 分页排版 / 行距段距首行缩进
- ✅ 设置面板（字体大小、颜色、背景、行距）
- ✅ 整窗透明（Ctrl + 滚轮调节）
- ✅ 无边框 / 全屏 / 置顶
- ✅ 全局热键 Option + H 显隐
- ✅ 书签（per-file）+ 章节跳转目录
- ✅ 会话恢复（重启自动打开上次的书 + 阅读位置）
- ⏳ 在线书源（爬虫核心已搭好接口，UI 待补）

## 安装

### 方式 1：Homebrew Cask（推荐，自动绕过 Gatekeeper）

```bash
brew tap WeirdoMeng/tap
brew install --cask reader-mac
```

### 方式 2：下载 DMG

去 [Releases](https://github.com/WeirdoMeng/Reader-Mac/releases) 下载最新版本的 `Reader-Mac-x.y.z.dmg`，挂载后拖到 Applications。

由于未购买 Apple 开发者证书做公证，首次启动会被 Gatekeeper 拦截。两种解决方法：

**方法 A**：右键 `Reader-Mac.app` → 选 **Open**，确认弹窗 → 一次性绕过。

**方法 B**：在终端执行（剥离 quarantine 属性）：
```bash
xattr -dr com.apple.quarantine /Applications/Reader-Mac.app
```

### 方式 3：从源码编译

```bash
git clone https://github.com/WeirdoMeng/Reader-Mac.git
cd Reader-Mac
cmake -S ReaderCore -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
open build/ReaderApp/ReaderMac.app
```

依赖：Xcode Command Line Tools、CMake ≥ 3.20。

## 快捷键

### 阅读
| 按键 | 作用 |
|---|---|
| ← / → | 上一页 / 下一页 |
| ↑ / ↓ | 行滚动 |
| Ctrl + ← / → | 上一章 / 下一章 |
| 鼠标左键 | 下一页 |
| 鼠标右键 | 上一页 |
| 滚轮 | 行滚动 |
| Ctrl + 滚轮 | 整窗透明度 ± 0.05 |
| Ctrl + Shift + 滚轮 | 透明度极值切换 |

### 菜单
| 按键 | 作用 |
|---|---|
| Cmd + O | 打开文件 |
| Cmd + W | 关闭当前书 |
| Cmd + , | 显示设置面板 |
| Cmd + Shift + B | 切换无边框 |
| Cmd + Ctrl + F | 切换全屏 |
| Cmd + T | 切换置顶 |
| Cmd + [ / ] | 上一章 / 下一章 |
| Cmd + M | 添加书签 |
| Option + H | 全局显示/隐藏 |
| Cmd + Q | 退出 |

## 项目结构

```
Reader-Mac/
├── ReaderCore/              # C++ 业务核心（跨平台静态库）
│   ├── include/reader/      # 公共头：types/page/book/utils/...
│   ├── src/                 # 平台无关实现
│   ├── platform/macos/      # macOS 专属（NSURLSession 桥等）
│   ├── third_party/         # cjson/miniz/minizip/libmobi/doctest
│   ├── tests/               # doctest 单元测试
│   └── CMakeLists.txt
├── ReaderApp/               # macOS 应用（ObjC++ + AppKit + Core Text）
│   ├── src/                 # AppDelegate / ReaderCanvasView / Preferences …
│   └── Resources/Info.plist
├── ReaderCli/               # 命令行 smoke test（无 UI 验证业务核心）
├── scripts/
│   └── make_dmg.sh          # 一键打包 DMG
└── dist/
    └── cask/reader-mac.rb   # Homebrew Cask 模板
```

## 架构亮点

- **业务核心 100% 跨平台**：Page 分页引擎、Book 系列、HtmlParser、Utils 完全脱离 GDI，
  通过 `ITextMetrics` 接口注入文字测量实现
- **依赖锐减**：原项目用 libhttps + wolfssl，本项目改用 NSURLSession + Apple SecureTransport，
  zlib + libxml2 走 macOS SDK 自带版本
- **可移植性**：CLI demo 可在任何 POSIX 平台运行，验证业务核心独立可用

## 测试

```bash
# 单元测试（12 用例覆盖 UTF8/16 互转 / base64 / url / BOM / XPath / 分页）
cmake --build build --target reader_core_tests -j
./build/reader_core_tests

# 命令行 smoke test
./build/ReaderCli/reader_cli /path/to/book.txt
```

## License

继承上游 [binbyu/Reader](https://github.com/binbyu/Reader) 项目协议。

## 移植说明

详见 commit 历史。关键里程碑：

- 第三方依赖 macOS 编译通过（8 库锐减为 4 + 系统库 2）
- ITextMetrics / IBookListener 接口抽象
- Page 引擎 1614 行去 GDI 化
- DecodeText 处理 macOS wchar_t = 4 字节与 Win UTF-16 互转
- NSURLSession 替代 libhttps + wolfssl
- ObjC++ 桥 + Core Text 渲染
- DMG 打包 + Homebrew Cask 模板
