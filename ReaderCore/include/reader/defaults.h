// ReaderCore: produce a header_t populated with reasonable defaults
// so the engine can run before Cache (full persistence) is ported.

#pragma once

#include "reader/types.h"

namespace reader {

// Fill `header` with sane defaults. Used by:
//   - Cache stub (until full Cache port lands)
//   - CLI smoke test
//   - unit tests
void fill_default_header(header_t* header);

}  // namespace reader
