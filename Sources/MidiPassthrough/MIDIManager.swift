import CoreMIDI
import Foundation
import os

struct MIDIDevice: Identifiable, Hashable {
    let id: Int32            // CoreMIDI unique ID, stable across launches
    let ref: MIDIEndpointRef
    let name: String
}

/// State read from the CoreMIDI callback thread.
private struct RealtimeState {
    var destination: MIDIEndpointRef = 0
    var passNotes = true
    var passClock = true
    var passCC = true
    var passPC = true
}

final class MIDIManager: ObservableObject {
    @Published private(set) var inputs: [MIDIDevice] = []
    @Published private(set) var outputs: [MIDIDevice] = []
    @Published private(set) var active = Array(repeating: false, count: 16)

    @Published var selectedInput: Int32? {
        didSet { if let d = inputs.first(where: { $0.id == selectedInput }) { inputName = d.name }; connectInput(); save() }
    }
    @Published var selectedOutput: Int32? {
        didSet { if let d = outputs.first(where: { $0.id == selectedOutput }) { outputName = d.name }; updateOutput(); save() }
    }
    @Published var passNotes = true { didSet { state.withLock { $0.passNotes = passNotes }; save() } }
    @Published var passClock = true { didSet { state.withLock { $0.passClock = passClock }; save() } }
    @Published var passCC = true { didSet { state.withLock { $0.passCC = passCC }; save() } }
    @Published var passPC = true { didSet { state.withLock { $0.passPC = passPC }; save() } }

    /// Last-used device names, kept so a device can be re-found if its unique ID changes.
    private var inputName: String?
    private var outputName: String?

    /// Saved selections whose devices are currently unplugged (shown in the pickers as "disconnected").
    var missingInput: MIDIDevice? { missing(selectedInput, inputName, in: inputs) }
    var missingOutput: MIDIDevice? { missing(selectedOutput, outputName, in: outputs) }

    private func missing(_ id: Int32?, _ name: String?, in list: [MIDIDevice]) -> MIDIDevice? {
        guard let id, let name, !list.contains(where: { $0.id == id }) else { return nil }
        return MIDIDevice(id: id, ref: 0, name: "\(name) (disconnected)")
    }

    private let state = OSAllocatedUnfairLock(initialState: RealtimeState())
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var connectedSource: MIDIEndpointRef = 0
    /// Held for the life of the app so macOS doesn't App Nap or coalesce timers while the window is hidden.
    private let activity = ProcessInfo.processInfo.beginActivity(
        options: [.userInitiated, .latencyCritical], reason: "Passing MIDI through")
    private var flashGeneration = Array(repeating: 0, count: 16)

    init() {
        let defaults = UserDefaults.standard
        // Property observers fire during init, so hold off saving until everything is loaded.
        selectedInput = (defaults.object(forKey: "inputID") as? Int).map { Int32($0) }
        selectedOutput = (defaults.object(forKey: "outputID") as? Int).map { Int32($0) }
        inputName = defaults.string(forKey: "inputName")
        outputName = defaults.string(forKey: "outputName")
        passNotes = defaults.object(forKey: "passNotes") as? Bool ?? true
        passClock = defaults.object(forKey: "passClock") as? Bool ?? true
        passCC = defaults.object(forKey: "passCC") as? Bool ?? true
        passPC = defaults.object(forKey: "passPC") as? Bool ?? true
        state.withLock { $0.passNotes = passNotes; $0.passClock = passClock; $0.passCC = passCC; $0.passPC = passPC }
        restoring = false

        MIDIClientCreateWithBlock("Midi Passthrough" as CFString, &client) { [weak self] notification in
            // Any change (added, removed, renamed, setup) can mean a device came or went.
            if notification.pointee.messageID != .msgIOError {
                DispatchQueue.main.async { self?.scheduleRefresh() }
            }
        }
        MIDIOutputPortCreate(client, "Output" as CFString, &outputPort)
        MIDIInputPortCreateWithProtocol(client, "Input" as CFString, ._1_0, &inputPort) { [weak self] list, _ in
            self?.handle(list)
        }
        refreshDevices()

        // Safety net: some drivers publish endpoints without a usable notification.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshDevices() }
    }

    // MARK: Devices

    private var refreshPending = false

    /// Coalesces bursts of notifications and waits for new endpoints to finish publishing their properties.
    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshPending = false
            self?.refreshDevices()
        }
    }

    private func refreshDevices() {
        let newInputs = (0..<MIDIGetNumberOfSources()).compactMap { Self.device(MIDIGetSource($0)) }
        let newOutputs = (0..<MIDIGetNumberOfDestinations()).compactMap { Self.device(MIDIGetDestination($0)) }
        let inputsChanged = newInputs != inputs
        if inputsChanged { inputs = newInputs }
        if newOutputs != outputs { outputs = newOutputs }

        // Re-find saved devices that came back, falling back to the saved name if the ID changed.
        if let d = resolve(selectedInput, inputName, in: inputs), d.id != selectedInput { selectedInput = d.id }
        if let d = resolve(selectedOutput, outputName, in: outputs), d.id != selectedOutput { selectedOutput = d.id }
        connectInput(force: inputsChanged)
        updateOutput()
    }

    private func resolve(_ id: Int32?, _ name: String?, in list: [MIDIDevice]) -> MIDIDevice? {
        guard id != nil else { return nil }
        return list.first { $0.id == id } ?? list.first { $0.name == name }
    }

    private var restoring = true

    private func save() {
        guard !restoring else { return }
        let d = UserDefaults.standard
        d.set(selectedInput.map { Int($0) }, forKey: "inputID")
        d.set(selectedOutput.map { Int($0) }, forKey: "outputID")
        d.set(inputName, forKey: "inputName")
        d.set(outputName, forKey: "outputName")
        d.set(passNotes, forKey: "passNotes")
        d.set(passClock, forKey: "passClock")
        d.set(passCC, forKey: "passCC")
        d.set(passPC, forKey: "passPC")
    }

    private static func device(_ ref: MIDIEndpointRef) -> MIDIDevice? {
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(ref, kMIDIPropertyDisplayName, &name)
        var uid: Int32 = 0
        MIDIObjectGetIntegerProperty(ref, kMIDIPropertyUniqueID, &uid)
        guard let name = name?.takeRetainedValue() else { return nil }
        return MIDIDevice(id: uid, ref: ref, name: name as String)
    }

    /// `force` re-subscribes even if the endpoint ref looks unchanged, since CoreMIDI can reuse refs after a replug.
    private func connectInput(force: Bool = false) {
        let source = inputs.first { $0.id == selectedInput }?.ref ?? 0
        guard force || source != connectedSource else { return }
        if connectedSource != 0 { MIDIPortDisconnectSource(inputPort, connectedSource) }
        if source != 0 { MIDIPortConnectSource(inputPort, source, nil) }
        connectedSource = source
    }

    private func updateOutput() {
        let destination = outputs.first { $0.id == selectedOutput }?.ref ?? 0
        state.withLock { $0.destination = destination }
    }

    // MARK: Passthrough (runs on the CoreMIDI thread)

    /// Words per Universal MIDI Packet, indexed by message type.
    private static let umpWordCount = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]

    private func handle(_ list: UnsafePointer<MIDIEventList>) {
        let s = state.withLock { $0 }
        guard s.destination != 0 else { return }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 1024, alignment: 8)
        defer { buffer.deallocate() }
        let outList = buffer.bindMemory(to: MIDIEventList.self, capacity: 1)
        var channels: UInt16 = 0

        for packet in list.unsafeSequence() {
            let wordsOffset = MemoryLayout<MIDIEventPacket>.offset(of: \.words)!
            let wordsPointer = (UnsafeRawPointer(packet) + wordsOffset).assumingMemoryBound(to: UInt32.self)
            let words = Array(UnsafeBufferPointer(start: wordsPointer, count: Int(packet.pointee.wordCount)))
            let timeStamp = packet.pointee.timeStamp
            var i = 0
            while i < words.count {
                let word = words[i]
                let type = Int(word >> 28)
                let count = min(Self.umpWordCount[type], words.count - i)
                defer { i += count }

                switch type {
                case 1 where (word >> 16) & 0xFF == 0xF8 && !s.passClock:
                    continue
                case 2:
                    let status = (word >> 20) & 0xF
                    if ((status == 0x8 || status == 0x9) && !s.passNotes) || (status == 0xB && !s.passCC) || (status == 0xC && !s.passPC) { continue }
                    channels |= 1 << UInt16((word >> 16) & 0xF)
                default:
                    break
                }

                var cursor = MIDIEventListInit(outList, ._1_0)
                cursor = words[i..<(i + count)].withUnsafeBufferPointer {
                    MIDIEventListAdd(outList, 1024, cursor, timeStamp, count, $0.baseAddress!)
                }
                MIDISendEventList(outputPort, s.destination, outList)
            }
        }

        if channels != 0 {
            DispatchQueue.main.async { [weak self] in self?.flash(channels) }
        }
    }

    // MARK: LEDs

    private func flash(_ channels: UInt16) {
        for channel in 0..<16 where channels & (1 << UInt16(channel)) != 0 {
            active[channel] = true
            flashGeneration[channel] += 1
            let generation = flashGeneration[channel]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, self.flashGeneration[channel] == generation else { return }
                self.active[channel] = false
            }
        }
    }
}
