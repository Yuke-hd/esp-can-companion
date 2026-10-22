#include "wav_reader.h"

#include <cstring>

namespace {
uint32_t le32(const uint8_t *p) { return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24); }
uint16_t le16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
}

bool readWavPcm16Mono(const uint8_t *bytes, size_t size, std::vector<int16_t> *samples) {
    if (size < 12 || memcmp(bytes, "RIFF", 4) != 0 || memcmp(bytes + 8, "WAVE", 4) != 0) return false;

    bool formatOk = false;
    size_t pos = 12;
    while (pos + 8 <= size) {
        const uint32_t chunkSize = le32(bytes + pos + 4);
        const uint8_t *body = bytes + pos + 8;
        if (pos + 8 + (size_t)chunkSize > size) return false;

        if (memcmp(bytes + pos, "fmt ", 4) == 0 && chunkSize >= 16) {
            formatOk = le16(body) == 1 && le16(body + 2) == 1 && le16(body + 14) == 16;
        }
        else if (memcmp(bytes + pos, "data", 4) == 0) {
            if (!formatOk) return false;
            const size_t n = chunkSize / 2;
            samples->resize(n);
            for (size_t i = 0; i < n; ++i) (*samples)[i] = (int16_t)le16(body + 2 * i);
            return true;
        }
        pos += 8 + chunkSize + (chunkSize & 1);
    }
    return false;
}
