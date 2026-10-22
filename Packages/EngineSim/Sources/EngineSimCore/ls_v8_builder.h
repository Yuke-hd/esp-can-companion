#ifndef ENGINE_SIM_CORE_LS_V8_BUILDER_H
#define ENGINE_SIM_CORE_LS_V8_BUILDER_H

#include <memory>
#include <vector>

class Engine;
class Vehicle;
class Transmission;
class Function;
class Camshaft;
class Valvetrain;
class ImpulseResponse;
class Simulator;

// Hand port of engine-sim assets/engines/atg-video-2/07_gm_ls.mr (the Piranha
// scripting layer is not vendored). Owns everything the script nodes would
// have heap-allocated beyond the Engine itself.
struct LsV8 {
    Engine *engine = nullptr;
    Vehicle *vehicle = nullptr;
    Transmission *transmission = nullptr;
    std::vector<Function *> functions;
    std::vector<Camshaft *> camshafts;
    std::vector<Valvetrain *> valvetrains;
    std::vector<ImpulseResponse *> impulseResponses;
};

void buildLsV8(LsV8 *ls);
void destroyLsV8(LsV8 *ls);

#endif
