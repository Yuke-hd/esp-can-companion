#ifndef ENGINE_SIM_CORE_WAV_READER_H
#define ENGINE_SIM_CORE_WAV_READER_H

#include <cstddef>
#include <cstdint>
#include <vector>

// Minimal RIFF/WAVE reader for impulse responses: PCM16 mono only.
bool readWavPcm16Mono(const uint8_t *bytes, size_t size, std::vector<int16_t> *samples);

#endif
