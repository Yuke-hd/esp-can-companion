#include "EngineSimCore.h"

#include "ls_v8_builder.h"
#include "ls_v8_impulse_response.h"
#include "wav_reader.h"

#include "engine.h"
#include "exhaust_system.h"
#include "ignition_module.h"
#include "impulse_response.h"
#include "piston_engine_simulator.h"
#include "synthesizer.h"

#include <chrono>
#include <cmath>
#include <condition_variable>
#include <mutex>
#include <thread>

struct EngineSimCore {
    LsV8 ls;
    PistonEngineSimulator *simulator = nullptr;
};

namespace {
constexpr double kFrameSeconds = 1.0 / 60.0;
constexpr auto kFrameTimeout = std::chrono::milliseconds(200);

// Blocks until the render thread has consumed this frame's input, so output is
// deterministic. The thread only signals when it had input to process.
void waitForRender(Synthesizer &synth) {
    std::unique_lock<std::mutex> lock(synth.m_lock0);
    synth.m_cv0.wait_for(lock, kFrameTimeout, [&synth] { return synth.m_processed; });
}
}

EngineSimCore *engine_sim_create_ls_v8(int simulationFrequency) {
    EngineSimCore *core = new EngineSimCore;
    buildLsV8(&core->ls);

    Engine *engine = core->ls.engine;
    core->simulator = static_cast<PistonEngineSimulator *>(
        engine->createSimulator(core->ls.vehicle, core->ls.transmission));
    PistonEngineSimulator *sim = core->simulator;

    sim->setSimulationFrequency(
        simulationFrequency > 0 ? simulationFrequency : (int)engine->getSimulationFrequency());

    Synthesizer::AudioParameters audio = sim->synthesizer().getAudioParameters();
    audio.inputSampleNoise = static_cast<float>(engine->getInitialJitter());
    audio.airNoise = static_cast<float>(engine->getInitialNoise());
    audio.dF_F_mix = static_cast<float>(engine->getInitialHighFrequencyGain());
    // Headroom: the leveler smooths its gain, so peaks overshoot the target and
    // clip at the stock 30000.
    audio.levelerTarget = 16000.0f;
    sim->synthesizer().setAudioParameters(audio);

    std::vector<int16_t> samples;
    if (readWavPcm16Mono(kLsV8ImpulseResponseWav, kLsV8ImpulseResponseWavSize, &samples)) {
        for (int i = 0; i < engine->getExhaustSystemCount(); ++i) {
            ImpulseResponse *response = engine->getExhaustSystem(i)->getImpulseResponse();
            sim->synthesizer().initializeImpulseResponse(
                samples.data(), (unsigned int)samples.size(), (float)response->getVolume(), i);
        }
    }

    sim->startAudioRenderingThread();
    return core;
}

void engine_sim_destroy(EngineSimCore *core) {
    if (core == nullptr) return;

    core->simulator->releaseSimulation();
    delete core->simulator;
    destroyLsV8(&core->ls);
    delete core;
}

void engine_sim_hold_rpm(EngineSimCore *core, double rpm) {
    core->ls.engine->getIgnitionModule()->m_enabled = true;
    core->ls.engine->setSpeedControl(0.5);
    core->simulator->m_dyno.m_enabled = true;
    core->simulator->m_dyno.m_hold = true;
    core->simulator->m_dyno.m_rotationSpeed = units::rpm(rpm);
}

// The leveler adapts its gain slowly (and boosts quiet passages up to 1.9x), so a
// sudden loud firing pulse can overshoot into hard clipping, which is audible as
// a crack. This stateless soft knee bends such peaks smoothly below full scale.
static void softLimit(int16_t *samples, int count) {
    constexpr float knee = 20000.0f;
    constexpr float headroom = 12000.0f;
    for (int i = 0; i < count; ++i) {
        const float x = samples[i];
        const float magnitude = std::fabs(x);
        if (magnitude <= knee) continue;
        const float limited = knee + headroom * std::tanh((magnitude - knee) / headroom);
        samples[i] = (int16_t)std::copysign(limited, x);
    }
}

static int renderLoop(EngineSimCore *core, int16_t *out, int sampleCount, bool synchronous) {
    PistonEngineSimulator *sim = core->simulator;
    int written = 0;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(30 + sampleCount / ENGINE_SIM_SAMPLE_RATE * 10);

    while (written < sampleCount && std::chrono::steady_clock::now() < deadline) {
        // Unlike a live player, this loop is not paced by playback. Without a limit,
        // physics outruns the synthesizer and overflows its input ring buffer, which
        // overwrites unread input and is heard as periodic cracks. Hold physics back
        // while enough input is queued.
        if (sim->getSynthesizerInputLatency() < sim->getTargetSynthesizerLatency()) {
            sim->startFrame(kFrameSeconds);
            while (sim->simulateStep()) { /* void */ }
            sim->endFrame();
            if (synchronous) waitForRender(sim->synthesizer());
        }
        else {
            // The render thread only wakes after an input block ends.
            sim->endFrame();
        }

        const int got = sim->readAudioOutput(sampleCount - written, out + written);
        softLimit(out + written, got);
        written += got;
        if (got == 0) std::this_thread::sleep_for(std::chrono::microseconds(500));
    }

    return written;
}

int engine_sim_render(EngineSimCore *core, int16_t *out, int sampleCount) {
    return renderLoop(core, out, sampleCount, false);
}

int engine_sim_render_synchronous(EngineSimCore *core, int16_t *out, int sampleCount) {
    return renderLoop(core, out, sampleCount, true);
}

double engine_sim_rpm(const EngineSimCore *core) {
    return core->ls.engine->getRpm();
}

int engine_sim_simulation_frequency(const EngineSimCore *core) {
    return core->simulator->getSimulationFrequency();
}
