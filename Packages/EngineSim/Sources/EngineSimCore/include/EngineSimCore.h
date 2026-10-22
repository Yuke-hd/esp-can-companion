#ifndef ENGINE_SIM_CORE_H
#define ENGINE_SIM_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct EngineSimCore EngineSimCore;

#define ENGINE_SIM_DEFAULT_FREQUENCY 10000
#define ENGINE_SIM_SAMPLE_RATE 44100

/// Builds the GM LS V8 with its exhaust impulse response and starts the audio thread.
/// `simulationFrequency` is the physics rate in Hz; 0 selects the default (10000).
EngineSimCore *engine_sim_create_ls_v8(int simulationFrequency);
void engine_sim_destroy(EngineSimCore *core);

/// Enables ignition and the dynamometer and holds the crankshaft at `rpm`.
void engine_sim_hold_rpm(EngineSimCore *core, double rpm);

/// Renders exactly `sampleCount` mono 16-bit samples at 44.1 kHz into `out`.
/// Returns the number of samples written (less than requested only on timeout).
int engine_sim_render(EngineSimCore *core, int16_t *out, int sampleCount);

double engine_sim_rpm(const EngineSimCore *core);
int engine_sim_simulation_frequency(const EngineSimCore *core);

#ifdef __cplusplus
}
#endif

#endif
