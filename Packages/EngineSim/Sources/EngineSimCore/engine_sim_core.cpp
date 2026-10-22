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
#include <condition_variable>
#include <mutex>

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
    audio.levelerTarget = 20000.0f;
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

int engine_sim_render(EngineSimCore *core, int16_t *out, int sampleCount) {
    PistonEngineSimulator *sim = core->simulator;
    int written = 0;
    int idleFrames = 0;

    while (written < sampleCount && idleFrames < 600) {
        sim->startFrame(kFrameSeconds);
        while (sim->simulateStep()) { /* void */ }
        sim->endFrame();
        waitForRender(sim->synthesizer());

        const int got = sim->readAudioOutput(sampleCount - written, out + written);
        written += got;
        idleFrames = (got == 0) ? idleFrames + 1 : 0;
    }

    return written;
}

double engine_sim_rpm(const EngineSimCore *core) {
    return core->ls.engine->getRpm();
}

int engine_sim_simulation_frequency(const EngineSimCore *core) {
    return core->simulator->getSimulationFrequency();
}
