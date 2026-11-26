import AudioToolbox
import CoreAudio
import Foundation
import ReadbackCore
import Synchronization

/// Turns every other app's sound down while Readback reads ("Lower other sounds while
/// reading", off unless the person switches it on; chosen by the owner on 2026-11-25).
///
/// macOS has no public way to duck other apps, so this does what tapmix and AudioCap do: a
/// Core Audio process tap of everything except Readback, set to mute what it taps, played back
/// through a private aggregate device at a lower gain (`DuckingMix`). Readback's own voice
/// isn't in the tap, so it stays at full volume. The tap needs the System Audio Recording
/// permission, which macOS asks for the first time one starts; that's why the switch asks for
/// it as it's turned on. Nothing is recorded or kept: the audio only passes through.
///
/// It fails quiet in the safe direction: if anything is missing (Readback's own process, the
/// output device, a format it can read), nothing is lowered. If Readback dies while lowered,
/// the tap stops being read and `.mutedWhenTapped` lets every app play normally again.
@MainActor
final class OtherAudioLowerer {
    /// The real-time side: the gain it's heading for and where it is, shared with the audio
    /// thread without locks.
    private final class Gain: Sendable {
        let target = Atomic<UInt32>(Float(1).bitPattern)
        let current = Atomic<UInt32>(Float(0).bitPattern)
        func setTarget(_ value: Float) { target.store(value.bitPattern, ordering: .relaxed) }
    }

    private let gain = Gain()
    private let queue = DispatchQueue(label: "local.readback.other-audio", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var letGo: DispatchWorkItem?

    private var running: Bool { procID != nil }

    /// After a reading the sound comes back up through the tap, and the tap stays this long
    /// before it goes. Taking over is the moment that clicks (macOS cuts the apps' own output),
    /// so a run of replies takes over once, not once per reply. Chosen by the owner on 2026-11-25.
    static let linger: TimeInterval = 60

    /// Starts the tap with the sound at full volume, so the cut happens now, under the cue
    /// sound while a reading prepares, and not when the voice starts.
    func takeOver() {
        letGo?.cancel()
        // Full, running or not: a reading that starts inside the last fade out (`scheduleLetGo`)
        // cancels the teardown, and the target would otherwise stay at silence while it prepares.
        gain.setTarget(1)
        if !running {
            guard start() else { return }
        }
    }

    /// Down to `DuckingMix.loweredGain`, easing there.
    func lower() {
        letGo?.cancel()
        if !running {
            guard start() else { return }
        }
        gain.setTarget(DuckingMix.loweredGain)
    }

    /// Back up to full, easing there. The tap goes after `linger`, unless another reading starts.
    func restore() {
        guard running else { return }
        gain.setTarget(1)
        scheduleLetGo(after: Self.linger)
    }

    /// The switch went off: other sound comes back and the tap goes now, after only the short
    /// fade that keeps it from clicking. The linger is for a run of replies, not for this.
    func release() {
        guard running else { return }
        scheduleLetGo(after: 0)
    }

    /// Starts a tap at full volume and lets it go again, so macOS asks for the permission now,
    /// while the person is looking at the switch, not in the middle of a reply.
    func askPermission() {
        guard !running else { return }
        gain.setTarget(1)
        guard start() else { return }
        scheduleLetGo(after: 1.5)
    }

    /// Quitting: no time for a fade.
    func stopNow() {
        letGo?.cancel()
        stop()
    }

    /// Fades the playback out (`DuckingMix.edgeSeconds`), then takes the tap away, and the apps
    /// play by themselves again from silence rather than over a jump.
    private func scheduleLetGo(after seconds: TimeInterval) {
        letGo?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                self.gain.setTarget(0)
                let stop = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.stop() } }
                self.letGo = stop
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: stop)
            }
        }
        letGo = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: Setting up and taking down

    private func start() -> Bool {
        guard let me = Self.processObject(pid: getpid()) else {
            Log.error("lower other sounds: Readback's own audio process wasn't found, so nothing is lowered")
            return false
        }
        guard let output = Self.defaultOutputDevice(), let outputUID = Self.uid(of: output) else {
            Log.error("lower other sounds: no output device")
            return false
        }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [me])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        description.name = "Readback lowers other sounds"
        var newTap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &newTap)
        guard status == noErr, newTap != kAudioObjectUnknown else {
            Log.error("lower other sounds: couldn't create the tap (\(status))")
            return false
        }
        guard let format = Self.tapFormat(newTap), format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
              format.mBitsPerChannel == 32, (1...2).contains(format.mChannelsPerFrame) else {
            AudioHardwareDestroyProcessTap(newTap)
            Log.error("lower other sounds: the tap's format isn't one it can play back")
            return false
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Readback lowers other sounds",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceClockDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        var newAggregate = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &newAggregate)
        guard status == noErr, newAggregate != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(newTap)
            Log.error("lower other sounds: couldn't create the playback device (\(status))")
            return false
        }

        let rate = Self.sampleRate(of: newAggregate)
        // From silence: macOS cuts the other apps' own output the moment the tap starts, and
        // this fades in under that cut instead of jumping in at full level.
        gain.current.store(Float(0).bitPattern, ordering: .relaxed)
        var newProc: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&newProc, newAggregate, queue,
                                                    Self.playback(gain: gain, coefficient: DuckingMix.rampCoefficient(sampleRate: rate),
                                                                  edgeCoefficient: DuckingMix.edgeCoefficient(sampleRate: rate)))
        guard status == noErr, let newProc else {
            AudioHardwareDestroyAggregateDevice(newAggregate)
            AudioHardwareDestroyProcessTap(newTap)
            Log.error("lower other sounds: couldn't set up playback (\(status))")
            return false
        }
        Self.ignoreHardwareInputs(of: newAggregate, proc: newProc)

        status = AudioDeviceStart(newAggregate, newProc)
        guard status == noErr else {
            AudioDeviceDestroyIOProcID(newAggregate, newProc)
            AudioHardwareDestroyAggregateDevice(newAggregate)
            AudioHardwareDestroyProcessTap(newTap)
            Log.error("lower other sounds: couldn't start playback (\(status))")
            return false
        }
        tapID = newTap
        aggregateID = newAggregate
        procID = newProc
        watchOutputDevice()
        Log.info("lowering other sounds")
        return true
    }

    private func stop() {
        guard running || tapID != kAudioObjectUnknown else { return }
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        unwatchOutputDevice()
        gain.current.store(Float(0).bitPattern, ordering: .relaxed)
        Log.info("other sounds back to normal")
    }

    /// Headphones plugged in, or a different output picked: rebuild on the new device, heading
    /// for the same level, or the lowered sound would keep going to the old one.
    private func watchOutputDevice() {
        guard outputListener == nil else { return }
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                let target = self.gain.target.load(ordering: .relaxed)
                self.stop()
                self.gain.target.store(target, ordering: .relaxed)
                _ = self.start()
            }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) == noErr {
            outputListener = listener
        }
    }

    private func unwatchOutputDevice() {
        guard let outputListener else { return }
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, outputListener)
        self.outputListener = nil
    }

    /// The audio callback. Built outside the main actor on purpose: Core Audio calls it on its
    /// own real-time thread, and a closure made in main-actor code could be held to the main
    /// actor and trap there. It eases from the shared gain toward the target, quickly below the
    /// lowered level (fading in from silence or out to it) and slowly above it.
    private nonisolated static func playback(gain: Gain, coefficient: Float, edgeCoefficient: Float) -> AudioDeviceIOBlock {
        { _, input, _, output, _ in
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outputs = UnsafeMutableAudioBufferListPointer(output)
            // The tap's stream comes after any of the output device's own inputs.
            guard let tapBuffer = inputs.last, let data = tapBuffer.mData else {
                for buffer in outputs { if let d = buffer.mData { memset(d, 0, Int(buffer.mDataByteSize)) } }
                return
            }
            let channels = max(1, Int(tapBuffer.mNumberChannels))
            let frames = Int(tapBuffer.mDataByteSize) / (channels * MemoryLayout<Float>.size)
            var current = Float(bitPattern: gain.current.load(ordering: .relaxed))
            DuckingMix.render(tap: data.assumingMemoryBound(to: Float.self), tapChannels: channels, tapFrames: frames,
                              into: outputs, target: Float(bitPattern: gain.target.load(ordering: .relaxed)),
                              current: &current, coefficient: coefficient, edgeCoefficient: edgeCoefficient)
            gain.current.store(current.bitPattern, ordering: .relaxed)
        }
    }

    // MARK: Core Audio lookups

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObject(pid: pid_t) -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func uid(of device: AudioDeviceID) -> String? {
        var address = address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    private static func tapFormat(_ tap: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = address(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        return AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format) == noErr ? format : nil
    }

    private static func sampleRate(of device: AudioObjectID) -> Double {
        var address = address(kAudioDevicePropertyNominalSampleRate)
        var rate: Float64 = 48_000
        var size = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr && rate > 0 ? rate : 48_000
    }

    private static func streamCount(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = address(kAudioDevicePropertyStreams, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    /// An output device with a microphone (a USB headset) brings its input into the aggregate
    /// device; marking those streams unused keeps macOS from treating this as recording from
    /// the microphone, with its own prompt. Only the tap's streams are read. (After tapmix.)
    private static func ignoreHardwareInputs(of aggregate: AudioObjectID, proc: AudioDeviceIOProcID) {
        let inputs = streamCount(aggregate, scope: kAudioObjectPropertyScopeInput)
        let outputs = streamCount(aggregate, scope: kAudioObjectPropertyScopeOutput)
        guard inputs > 0, outputs > 0, inputs > outputs else { return }
        let header = MemoryLayout<UnsafeMutableRawPointer>.size + MemoryLayout<UInt32>.size
        let total = header + inputs * MemoryLayout<UInt32>.size
        let raw = UnsafeMutableRawPointer.allocate(byteCount: total, alignment: MemoryLayout<UnsafeMutableRawPointer>.alignment)
        defer { raw.deallocate() }
        raw.storeBytes(of: unsafeBitCast(proc, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        raw.storeBytes(of: UInt32(inputs), toByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size, as: UInt32.self)
        for i in 0..<inputs {
            let used: UInt32 = i >= inputs - outputs ? 1 : 0
            raw.storeBytes(of: used, toByteOffset: header + i * MemoryLayout<UInt32>.size, as: UInt32.self)
        }
        var address = address(kAudioDevicePropertyIOProcStreamUsage, scope: kAudioObjectPropertyScopeInput)
        AudioObjectSetPropertyData(aggregate, &address, 0, nil, UInt32(total), raw)
    }
}
