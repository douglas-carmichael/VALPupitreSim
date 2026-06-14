//
//  AudioEngine.swift
//  VALPupitreSim
//

import Foundation
import AVFoundation

/// Procedural audio synth driven from `SimulationModel`. A single
/// `AVAudioSourceNode` synthesises every voice — motor whine, brake hiss,
/// horn, compressor rumble, dead-man buzzer and door chime — directly into
/// the main mixer. No samples on disk required.
final class AudioEngine {

    private let engine = AVAudioEngine()
    private let sampleRate: Double = 48000

    // MARK: Live parameters (written from main, read by audio thread)

    var motorFreq: Double = 50
    var motorGain: Float = 0
    var brakeGain: Float = 0
    var hornGain: Float = 0
    var compressorGain: Float = 0
    var buzzerGain: Float = 0

    // MARK: Audio-thread-only state

    private var motorPhase: Double = 0
    private var motorPhase2: Double = 0
    private var hornPhase: Double = 0
    private var compressorPhase: Double = 0
    private var buzzerPhase: Double = 0
    private var buzzerGatePhase: Double = 0
    private var chimePhase: Double = 0
    private var chimeRemaining: Float = 0
    private var noiseFiltered: Float = 0
    private var noiseState: UInt32 = 0xC0FFEE

    // MARK: Lifecycle

    func start() {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 1,
                                         interleaved: false) else { return }
        let source = AVAudioSourceNode(format: format) { [weak self] _, _, frames, abl -> OSStatus in
            guard let self else { return noErr }
            let dt = 1.0 / self.sampleRate
            let bufs = UnsafeMutableAudioBufferListPointer(abl)
            for buf in bufs {
                let samples = buf.mData!.assumingMemoryBound(to: Float.self)
                for i in 0..<Int(frames) {
                    samples[i] = self.renderSample(dt: dt)
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.55
        do {
            try engine.start()
        } catch {
            print("AudioEngine failed to start: \(error)")
        }
    }

    func stop() { engine.stop() }

    /// Mute/unmute by gating the main mixer's output volume.
    func setMuted(_ muted: Bool) {
        engine.mainMixerNode.outputVolume = muted ? 0 : 0.55
    }

    /// Triggered when doors begin to open or close.
    func triggerDoorChime() { chimeRemaining = 0.85 }

    /// Snapshot model state into live audio parameters. Call once per frame.
    func update(model: SimulationModel) {
        let r = min(1, model.speedMS / model.maxSpeedMS)
        motorFreq = 32 + r * 320
        var mg = model.kg ? Float(0.025 + r * 0.32) : 0
        if model.voyantTraction { mg *= 1.25 }
        motorGain = min(mg, 0.42)

        var br: Float = 0
        if model.voyantFreinage { br = Float(0.12 + abs(model.masterController) * 0.32) }
        if model.emergencyBrake { br = max(br, 0.55) }
        if !model.kg { br *= 0.3 }
        brakeGain = br

        hornGain = model.hornPressed ? 0.42 : 0
        compressorGain = model.kg ? 0.045 : 0
        buzzerGain = model.deadmanWarning ? 0.4 : 0
    }

    // MARK: Audio render

    /// Cheap deterministic noise — avoids the locking RNG in `Float.random`.
    private func nextNoise() -> Float {
        noiseState ^= noiseState << 13
        noiseState ^= noiseState >> 17
        noiseState ^= noiseState << 5
        return Float(Int32(bitPattern: noiseState)) / Float(Int32.max)
    }

    private func renderSample(dt: Double) -> Float {
        var s: Float = 0
        let twoPi = 2.0 * .pi

        if motorGain > 0.0005 {
            motorPhase += motorFreq * dt
            if motorPhase >= 1 { motorPhase -= 1 }
            motorPhase2 += motorFreq * 2.0 * dt
            if motorPhase2 >= 1 { motorPhase2 -= 1 }
            let tri  = Float(2 * abs(2 * motorPhase  - 1) - 1)
            let tri2 = Float(2 * abs(2 * motorPhase2 - 1) - 1)
            s += motorGain * (tri * 0.55 + tri2 * 0.28)
        }

        if brakeGain > 0.0005 {
            let n = nextNoise()
            noiseFiltered = noiseFiltered * 0.88 + n * 0.12
            s += brakeGain * noiseFiltered
        }

        if hornGain > 0.0005 {
            hornPhase += 220 * dt
            if hornPhase >= 1 { hornPhase -= 1 }
            let a = Float(sin(hornPhase * twoPi))
            let b = Float(sin(hornPhase * twoPi * 1.5))
            s += hornGain * (a * 0.55 + b * 0.3)
        }

        if compressorGain > 0.0005 {
            compressorPhase += 55 * dt
            if compressorPhase >= 1 { compressorPhase -= 1 }
            s += compressorGain * Float(sin(compressorPhase * twoPi))
        }

        if buzzerGain > 0.0005 {
            buzzerPhase += 1500 * dt
            if buzzerPhase >= 1 { buzzerPhase -= 1 }
            buzzerGatePhase += 4 * dt
            if buzzerGatePhase >= 1 { buzzerGatePhase -= 1 }
            let tone = Float(sin(buzzerPhase * twoPi))
            let gate: Float = buzzerGatePhase < 0.5 ? 1 : 0
            s += buzzerGain * tone * gate * 0.6
        }

        if chimeRemaining > 0 {
            chimePhase += 660 * dt
            if chimePhase >= 1 { chimePhase -= 1 }
            let env = chimeRemaining / 0.85
            s += Float(sin(chimePhase * twoPi)) * env * 0.35
            chimeRemaining -= Float(dt)
        }

        return tanh(s * 0.9)
    }
}
