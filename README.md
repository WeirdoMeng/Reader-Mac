# Reader-Mac

将 [binbyu/Reader](https://github.com/binbyu/Reader) Windows 桌面阅读器移植为原生 macOS 应用。

## 项目结构

```
Reader-Mac/
├── ReaderCore/              # C++ 业务核心（跨平台静态库）
│   ├── src/                 # 移植自原 Reader/ 的业务逻辑
│   ├── platform/macos/      # macOS 专属接口实现（Core Text 等）
│   ├── third_party/         # 第三方库源码 + 构建脚本
│   └── CMakeLists.txt
├── ReaderApp/               # macOS 应用（SwiftUI + AppKit）
└── scripts/
    └── build_third_party.sh # 一键构建所有 C/C++ 第三方依赖
```

## 当前进度

- [x] 项目骨架
- [ ] 第三方库 macOS 编译（cjson / miniz / zlib / libxml2 / wolfssl / libhttps / libmobi）
- [ ] C++ 业务核心移植（Book / Page / Cache / HtmlParser 等）
- [ ] Objective-C++ 桥
- [ ] macOS 应用骨架
- [ ] 翻页 / 设置 / 在线书源 / 全局热键 / 透明窗口

## 构建

依赖：Xcode Command Line Tools、CMake ≥ 3.20。

```bash
./scripts/build_third_party.sh
cmake -S ReaderCore -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

## 安装说明（开源版，未签名）

本项目为开源软件，未购买 Apple 开发者证书。首次打开时 macOS 会拦截：

**方式 1**：在 Finder 中右键 `Reader.app` → 选"打开"。

**方式 2**：在终端执行 `xattr -dr com.apple.quarantine /Applications/Reader.app`。

**方式 3**：从源码自行编译（无任何提示）。

## License

继承上游：见原项目说明。
