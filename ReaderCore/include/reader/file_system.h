// ReaderCore: thin file-system helpers.
// Path types are TCHAR-based (wchar_t on POSIX, native on Win) for source
// parity with the original code.

#pragma once

#include "reader/platform.h"

namespace reader {
namespace fs {

// Read entire file into a heap-allocated buffer. Caller frees with free().
// Returns nullptr on failure; *out_size is set to file size in bytes.
char* read_all(const TCHAR* path, int* out_size);

// Write a buffer to a file (truncating). Returns true on success.
bool write_all(const TCHAR* path, const void* data, int size);

// Does the path exist?
bool exists(const TCHAR* path);

// Return the application's data directory, where .cache.dat lives.
// On macOS: ~/Library/Application Support/Reader-Mac/.
// On Win: directory of the .exe (matches original behavior).
// Buffer must be MAX_PATH wchar_t's.
void get_app_data_dir(TCHAR* out_dir);

}  // namespace fs
}  // namespace reader
