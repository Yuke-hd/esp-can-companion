#include "ls_v8_builder.h"

#include "engine.h"
#include "vehicle.h"
#include "transmission.h"
#include "crankshaft.h"
#include "cylinder_bank.h"
#include "cylinder_head.h"
#include "piston.h"
#include "connecting_rod.h"
#include "intake.h"
#include "exhaust_system.h"
#include "camshaft.h"
#include "standard_valvetrain.h"
#include "ignition_module.h"
#include "direct_throttle_linkage.h"
#include "fuel.h"
#include "function.h"
#include "gas_system.h"
#include "impulse_response.h"
#include "combustion_chamber.h"
#include "constants.h"
#include "units.h"

#include <cmath>

namespace {

double rodMomentOfInertia(double mass, double length) { return (1.0 / 12.0) * mass * length * length; }
double diskMomentOfInertia(double mass, double radius) { return 0.5 * mass * radius * radius; }
double circleArea(double r) { return constants::pi * r * r; }

Function *newFunction(LsV8 *ls, int size, double filterRadius) {
    Function *f = new Function;
    f->initialize(size, filterRadius);
    ls->functions.push_back(f);
    return f;
}

// harmonic_cam_lobe from actions.h (GenerateHarmonicCamLobeNode).
Function *harmonicCamLobe(LsV8 *ls, double durationAt50Thou, double gamma, double lift, int steps) {
    const double angle = durationAt50Thou / 4;
    const double s = std::pow(2 * units::distance(50, units::thou) / lift, 1 / gamma) - 1;
    const double k = std::acos(s) / angle;
    const double extents = constants::pi / k;
    const double step = extents / (steps - 5.0);

    Function *f = newFunction(ls, 2 * steps, step);
    for (int i = 0; i < steps; ++i) {
        if (i == 0) {
            f->addSample(0.0, lift);
        }
        else {
            const double x = i * step;
            const double l = (x >= extents) ? 0.0 : lift * std::pow(0.5 + 0.5 * std::cos(k * x), gamma);
            f->addSample(x, l);
            f->addSample(-x, l);
        }
    }
    return f;
}

Function *portFlow(LsV8 *ls, const double (&thouAndScfm)[10][2]) {
    Function *f = newFunction(ls, 10, units::distance(50, units::thou));
    for (const auto &sample : thouAndScfm) {
        f->addSample(sample[0] * units::thou, GasSystem::k_28inH2O(sample[1]));
    }
    return f;
}

const double kIntakeFlow[10][2] = {
    {0, 0}, {50, 1}, {100, 103}, {150, 156}, {200, 214},
    {250, 249}, {300, 268}, {350, 280}, {400, 280}, {450, 281},
};
const double kExhaustFlow[10][2] = {
    {0, 0}, {50, 1}, {100, 72}, {150, 113}, {200, 160},
    {250, 196}, {300, 222}, {350, 235}, {400, 245}, {450, 246},
};

// ls_v8_camshaft node: cam 0 serves cylinders 1 3 5 7, cam 1 serves 2 4 6 8.
// Cylinder order within a bank is the script's add_cylinder order.
const int kCam0Offsets[4] = {0, 7, 5, 2};
const int kCam1Offsets[4] = {3, 6, 4, 1};

Camshaft *newCamshaft(LsV8 *ls, Crankshaft *crank, Function *profile, const int (&offsets)[4], double sign, double lobeCenter) {
    Camshaft::Parameters p;
    p.crankshaft = crank;
    p.lobes = 4;
    p.lobeProfile = profile;
    p.advance = 0.0;
    p.baseRadius = units::distance(1.0, units::inch);

    Camshaft *cam = new Camshaft;
    cam->initialize(p);
    const double rot = 90 * units::deg;
    const double rot360 = 360 * units::deg;
    for (int i = 0; i < 4; ++i) {
        cam->setLobeCenterline(i, rot360 + sign * lobeCenter + offsets[i] * rot);
    }
    ls->camshafts.push_back(cam);
    return cam;
}

} // namespace

void buildLsV8(LsV8 *ls) {
    const double stroke = units::distance(3.622, units::inch);
    const double bore = units::distance(3.78, units::inch);
    const double rodLength = units::distance(160, units::mm);
    const double rodMass = units::mass(50, units::g);
    const double compressionHeight = units::distance(1.0, units::inch);
    const double crankMass = units::mass(60, units::lb);
    const double flywheelMass = units::mass(30, units::lb);
    const double flywheelRadius = units::distance(8, units::inch);
    const double vAngle = 90 * units::deg;
    const double spacing = units::distance(2, units::inch);
    const double cm = units::cm;

    // Engine::Parameters and Fuel (engine node "engine(...)").
    Engine *engine = new Engine;
    ls->engine = engine;

    DirectThrottleLinkage::Parameters throttleParams;
    throttleParams.gamma = 2.0;
    DirectThrottleLinkage *throttle = new DirectThrottleLinkage;
    throttle->initialize(throttleParams);

    Engine::Parameters ep;
    ep.name = "GM LS";
    ep.starterTorque = units::torque(200, units::ft_lb);
    ep.starterSpeed = units::rpm(200);
    ep.redline = units::rpm(6500);
    ep.dynoMinSpeed = units::rpm(1000);
    ep.dynoMaxSpeed = ep.redline;
    ep.dynoHoldStep = units::rpm(100);
    ep.initialSimulationFrequency = 10000;
    ep.initialHighFrequencyGain = 0.01;
    ep.initialNoise = 1.0;
    ep.initialJitter = 0.6;
    ep.crankshaftCount = 1;
    ep.cylinderBanks = 2;
    ep.cylinderCount = 8;
    ep.exhaustSystemCount = 2;
    ep.intakeCount = 1;
    ep.throttle = throttle;
    engine->initialize(ep);

    // Crankshaft c0.
    Crankshaft::Parameters cp;
    cp.crankThrow = stroke / 2;
    cp.flywheelMass = flywheelMass;
    cp.mass = crankMass;
    cp.frictionTorque = units::torque(20.0, units::ft_lb);
    cp.momentOfInertia = 1.5 * diskMomentOfInertia(crankMass, stroke)
        + diskMomentOfInertia(flywheelMass, flywheelRadius)
        + diskMomentOfInertia(1.0, 0.01);
    cp.pos_x = 0.0;
    cp.pos_y = 0.0;
    cp.tdc = 90 * units::deg - (vAngle / 2.0);
    cp.rodJournals = 4;
    Crankshaft *crank = engine->getCrankshaft(0);
    crank->initialize(cp);
    const double journalAngles[4] = {0 * units::deg, 270 * units::deg, 90 * units::deg, 180 * units::deg};
    for (int i = 0; i < 4; ++i) crank->setRodJournalAngle(i, journalAngles[i]);

    // Cylinder banks: b0 at -45 deg (wires 1 3 5 7), b1 at +45 deg (wires 2 4 6 8).
    const double deckHeight = stroke / 2 + rodLength + compressionHeight;
    const double bankAngles[2] = {-vAngle / 2.0, vAngle / 2.0};
    for (int b = 0; b < 2; ++b) {
        CylinderBank::Parameters bp;
        bp.crankshaft = crank;
        bp.positionX = 0.0;
        bp.positionY = 0.0;
        bp.angle = bankAngles[b];
        bp.bore = bore;
        bp.deckHeight = deckHeight;
        bp.displayDepth = 0.6;
        bp.cylinderCount = 4;
        bp.index = b;
        engine->getCylinderBank(b)->initialize(bp);
    }

    // Per-cylinder values, in each bank's add_cylinder order.
    const int rodJournalIndex[4] = {0, 1, 2, 3};
    const double primaryLength[2][4] = {
        {3 * spacing + 2 * cm, 2 * spacing + 1 * cm, 1 * spacing + 3 * cm, 0 * spacing + 5 * cm},
        {3 * spacing + 1 * cm, 2 * spacing + 5 * cm, 1 * spacing + 7 * cm, 0 * spacing + 0 * cm},
    };

    for (int b = 0; b < 2; ++b) {
        for (int i = 0; i < 4; ++i) {
            const int index = b * 4 + i;
            Piston *piston = engine->getPiston(index);
            ConnectingRod *rod = engine->getConnectingRod(index);

            Piston::Parameters pp;
            pp.mass = units::mass(100, units::g);
            pp.CompressionHeight = compressionHeight;
            pp.WristPinPosition = 0.0;
            pp.Displacement = 0.0;
            pp.BlowbyFlowCoefficient = GasSystem::k_28inH2O(0.0);
            pp.Bank = engine->getCylinderBank(b);
            pp.CylinderIndex = i;
            pp.Rod = rod;
            piston->initialize(pp);

            ConnectingRod::Parameters rp;
            rp.mass = rodMass;
            rp.momentOfInertia = rodMomentOfInertia(rodMass, rodLength);
            rp.centerOfMass = 0.0;
            rp.length = rodLength;
            rp.slaveThrow = 0.0;
            rp.crankshaft = crank;
            rp.journal = rodJournalIndex[i];
            rp.piston = piston;
            rp.rodJournals = 0;
            rp.master = nullptr;
            rod->initialize(rp);
        }
    }

    // Intake and exhaust systems.
    Intake::Parameters ip;
    ip.volume = units::volume(1.325, units::L);
    ip.CrossSectionArea = units::area(20.0, units::cm2);
    ip.InputFlowK = GasSystem::k_carb(700.0);
    ip.RunnerFlowRate = GasSystem::k_carb(100.0);
    ip.RunnerLength = units::distance(12.0, units::inch);
    ip.IdleFlowK = GasSystem::k_carb(0.0);
    ip.IdleThrottlePlatePosition = 0.996;
    ip.VelocityDecay = 0.5;
    Intake *intake = engine->getIntake(0);
    intake->initialize(ip);

    ImpulseResponse *ir = new ImpulseResponse;
    ir->initialize("smooth/smooth_39.wav", 0.001);
    ls->impulseResponses.push_back(ir);

    const double exhaustLengths[2] = {units::distance(100, units::inch), units::distance(172, units::inch)};
    for (int e = 0; e < 2; ++e) {
        ExhaustSystem::Parameters xp;
        xp.outletFlowRate = GasSystem::k_carb(1000.0);
        xp.primaryTubeLength = units::distance(29.0, units::inch);
        xp.primaryFlowRate = GasSystem::k_carb(500.0);
        xp.velocityDecay = 1.0;
        xp.collectorCrossSectionArea = circleArea(units::distance(2.0, units::inch));
        xp.audioVolume = 4.0;
        xp.length = exhaustLengths[e];
        xp.impulseResponse = ir;
        engine->getExhaustSystem(e)->initialize(xp);
    }

    // Cylinder heads and valvetrains.
    Function *intakeLobe = harmonicCamLobe(ls, 234 * units::deg, 1.1, units::distance(551, units::thou), 256);
    Function *exhaustLobe = harmonicCamLobe(ls, 235 * units::deg, 1.1, units::distance(551, units::thou), 256);
    Function *intakeFlow = portFlow(ls, kIntakeFlow);
    Function *exhaustFlow = portFlow(ls, kExhaustFlow);
    const double lobeCenter = 116 * units::deg;

    for (int b = 0; b < 2; ++b) {
        const int (&offsets)[4] = (b == 0) ? kCam0Offsets : kCam1Offsets;
        Camshaft *intakeCam = newCamshaft(ls, crank, intakeLobe, offsets, +1.0, lobeCenter);
        Camshaft *exhaustCam = newCamshaft(ls, crank, exhaustLobe, offsets, -1.0, lobeCenter);

        StandardValvetrain::Parameters vp;
        vp.intakeCamshaft = intakeCam;
        vp.exhaustCamshaft = exhaustCam;
        StandardValvetrain *valvetrain = new StandardValvetrain;
        valvetrain->initialize(vp);
        ls->valvetrains.push_back(valvetrain);

        CylinderHead::Parameters hp;
        hp.Bank = engine->getCylinderBank(b);
        hp.Valvetrain = valvetrain;
        hp.IntakePortFlow = intakeFlow;
        hp.ExhaustPortFlow = exhaustFlow;
        hp.CombustionChamberVolume = units::volume(90, units::cc);
        hp.IntakeRunnerVolume = units::volume(149.6, units::cc);
        hp.IntakeRunnerCrossSectionArea = units::distance(2.2, units::inch) * units::distance(2.2, units::inch);
        hp.ExhaustRunnerVolume = units::volume(50.0, units::cc);
        hp.ExhaustRunnerCrossSectionArea = units::distance(1.75, units::inch) * units::distance(1.75, units::inch);
        hp.FlipDisplay = (b == 1);
        CylinderHead *head = engine->getHead(b);
        head->initialize(hp);

        for (int i = 0; i < 4; ++i) {
            head->setIntake(i, intake);
            head->setExhaustSystem(i, engine->getExhaustSystem(b));
            head->setSoundAttenuation(i, 1.0);
            head->setHeaderPrimaryLength(i, primaryLength[b][i]);
        }
    }

    // Ignition module. Firing order 1 8 7 2 6 5 4 3 at 90 deg spacing; bank b cylinder i
    // is wire (2*i+1) for b0 and (2*i+2) for b1.
    Function *timing = newFunction(ls, 9, units::rpm(1000));
    const double timingDeg[9] = {12, 12, 20, 30, 40, 40, 40, 40, 40};
    for (int i = 0; i < 9; ++i) timing->addSample(units::rpm(i * 1000.0), timingDeg[i] * units::deg);

    IgnitionModule::Parameters igp;
    igp.crankshaft = crank;
    igp.cylinderCount = 8;
    igp.timingCurve = timing;
    igp.revLimit = units::rpm(6800);
    igp.limiterDuration = 0.2;
    IgnitionModule *ignition = engine->getIgnitionModule();
    ignition->initialize(igp);
    const int firingWire[8] = {1, 8, 7, 2, 6, 5, 4, 3};
    for (int slot = 0; slot < 8; ++slot) {
        const int wire = firingWire[slot];
        const int bank = (wire % 2 == 1) ? 0 : 1;
        const int cylinder = (wire - 1) / 2;
        ignition->setFiringOrder(bank * 4 + cylinder, slot * 90 * units::deg);
    }

    // Fuel.
    Function *flame = newFunction(ls, 10, 5.0);
    flame->addSample(0.0, 3.0);
    const double flameRatio[9] = {1.5, 1.75, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0};
    for (int i = 0; i < 9; ++i) {
        const double x = 5.0 * (i + 1);
        flame->addSample(x, flameRatio[i] * x);
    }
    Fuel::Parameters fp;
    fp.maxBurningEfficiency = 1.0;
    fp.turbulenceToFlameSpeedRatio = flame;
    engine->getFuel()->initialize(fp);

    // Combustion chambers.
    Function *turbulence = newFunction(ls, 30, 1);
    for (int i = 0; i < 30; ++i) turbulence->addSample(i, i * 0.5);

    CombustionChamber::Parameters ccp;
    ccp.CrankcasePressure = units::pressure(1.0, units::atm);
    ccp.Fuel = engine->getFuel();
    ccp.StartingPressure = units::pressure(1.0, units::atm);
    ccp.StartingTemperature = units::celcius(25.0);
    ccp.MeanPistonSpeedToTurbulence = turbulence;
    for (int i = 0; i < engine->getCylinderCount(); ++i) {
        ccp.Piston = engine->getPiston(i);
        ccp.Head = engine->getHead(ccp.Piston->getCylinderBank()->getIndex());
        engine->getChamber(i)->initialize(ccp);
    }

    // Vehicle and transmission ("corvette").
    ls->vehicle = new Vehicle;
    Vehicle::Parameters vehicleParams;
    vehicleParams.mass = units::mass(1614, units::kg);
    vehicleParams.dragCoefficient = 0.3;
    vehicleParams.crossSectionArea = units::distance(72, units::inch) * units::distance(50, units::inch);
    vehicleParams.diffRatio = 3.42;
    vehicleParams.tireRadius = units::distance(10, units::inch);
    vehicleParams.rollingResistance = units::force(200, units::N);
    ls->vehicle->initialize(vehicleParams);

    ls->transmission = new Transmission;
    const double gears[6] = {2.97, 2.07, 1.43, 1.00, 0.71, 0.57};
    Transmission::Parameters tp;
    tp.GearCount = 6;
    tp.GearRatios = gears;
    tp.MaxClutchTorque = units::torque(500, units::ft_lb);
    ls->transmission->initialize(tp);

    engine->calculateDisplacement();
}

void destroyLsV8(LsV8 *ls) {
    if (ls->engine != nullptr) {
        ls->engine->destroy();
        delete ls->engine;
    }
    for (Camshaft *c : ls->camshafts) { c->destroy(); delete c; }
    for (Valvetrain *v : ls->valvetrains) delete v;
    for (Function *f : ls->functions) { f->destroy(); delete f; }
    for (ImpulseResponse *i : ls->impulseResponses) delete i;
    delete ls->vehicle;
    delete ls->transmission;
    *ls = LsV8();
}
