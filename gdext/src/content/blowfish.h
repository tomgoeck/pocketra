

#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace racontent {

class Blowfish {
public:
    explicit Blowfish(const uint8_t* key, size_t key_len);


    void decrypt(uint8_t* data, size_t len) const;
    void encrypt(uint8_t* data, size_t len) const;

private:
    uint32_t f(uint32_t x) const;
    void encrypt_words(uint32_t& l, uint32_t& r) const;
    void decrypt_words(uint32_t& l, uint32_t& r) const;

    uint32_t P[18];
    uint32_t S[4][256];
};


std::vector<uint8_t> decrypt_blowfish_key(const uint8_t* keyblock, size_t len);

}
