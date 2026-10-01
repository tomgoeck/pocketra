

#pragma once

#include <cstddef>
#include <cstdint>

namespace racontent {


long lcw_decode(const uint8_t* src, size_t src_len, size_t pos, uint8_t* dest, size_t dest_len,
                bool relative = false);


long xor_delta_decode(const uint8_t* src, size_t src_len, size_t pos, uint8_t* dest, size_t dest_len);

}
