//
//  HIDInputManager.swift
//  VALPupitreSim
//

import Foundation
import Observation

#if os(macOS)
import IOKit
import IOKit.hid

/// Reads input from any HID joystick / gamepad / multi-axis controller via
/// `IOHIDManager` and maps it to `SimulationModel`. The default mapping
/// matches a Raspberry Pi Pico configured as a 1-axis 12-button HID gamepad
/// (the device the pupitre PCB build log describes building):
///
/// - Buttons 1..12 → KG, KACOP, KIBS, KPH, horn, PO G, PO D, FP,
///   reverser AV, reverser 0, reverser AR, emergency brake.
/// - Axis Y → master controller (forward stick = +traction).
///
/// Under PCC command the desk is locked out: only the emergency brake
/// (button 12) still acts.
@Observable
final class HIDInputManager {

    var connectedDeviceName: String? = nil

    @ObservationIgnored weak var model: SimulationModel?
    @ObservationIgnored private var manager: IOHIDManager?

    init(model: SimulationModel) { self.model = model }

    func start() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr

        let matches: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey: kHIDUsage_GD_MultiAxisController]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matches as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, dev in
            guard let ctx else { return }
            let s = Unmanaged<HIDInputManager>.fromOpaque(ctx).takeUnretainedValue()
            s.deviceAttached(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, dev in
            guard let ctx else { return }
            let s = Unmanaged<HIDInputManager>.fromOpaque(ctx).takeUnretainedValue()
            s.deviceRemoved(dev)
        }, ctx)
        IOHIDManagerRegisterInputValueCallback(mgr, { ctx, _, _, value in
            guard let ctx else { return }
            let s = Unmanaged<HIDInputManager>.fromOpaque(ctx).takeUnretainedValue()
            s.handleInput(value)
        }, ctx)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func stop() {
        if let mgr = manager {
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    private func deviceName(_ dev: IOHIDDevice) -> String {
        (IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String) ?? "HID device"
    }

    private func deviceAttached(_ dev: IOHIDDevice) {
        connectedDeviceName = deviceName(dev)
    }

    private func deviceRemoved(_ dev: IOHIDDevice) {
        if connectedDeviceName == deviceName(dev) { connectedDeviceName = nil }
    }

    private func handleInput(_ value: IOHIDValue) {
        guard let model else { return }
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = Int(IOHIDElementGetUsage(element))
        let raw = IOHIDValueGetIntegerValue(value)

        if usagePage == UInt32(kHIDPage_Button) {
            applyButton(usage, pressed: raw != 0, model: model)
            return
        }

        if usagePage == UInt32(kHIDPage_GenericDesktop) {
            guard model.authority == .local else { return }
            let lo = IOHIDElementGetLogicalMin(element)
            let hi = IOHIDElementGetLogicalMax(element)
            let range = hi - lo
            guard range > 0 else { return }
            let normalized = Double(raw - lo) / Double(range)   // 0..1
            let bipolar = (normalized - 0.5) * 2.0              // -1..+1
            if usage == kHIDUsage_GD_Y {
                // Stick pushed forward (translation negative) → positive traction.
                model.masterController = max(-1, min(1, -bipolar))
            }
        }
    }

    private func applyButton(_ usage: Int, pressed: Bool, model: SimulationModel) {
        if model.authority == .pcc && usage != 12 { return }
        switch usage {
        case 1:  model.kg = pressed
        case 2:  model.kacop = pressed
        case 3:  model.kibs = pressed
        case 4:  model.kph = pressed
        case 5:  model.hornPressed = pressed
        case 6:  model.doorOpenLeft = pressed
        case 7:  model.doorOpenRight = pressed
        case 8:  model.doorClose = pressed
        case 9:  if pressed { model.direction = .forward }
        case 10: if pressed { model.direction = .neutral }
        case 11: if pressed { model.direction = .reverse }
        case 12: if pressed { model.emergencyBrake.toggle() }
        default: break
        }
    }
}

#else

/// Non-macOS stub so the project still compiles for iOS / Catalyst targets.
@Observable
final class HIDInputManager {
    var connectedDeviceName: String? = nil
    init(model: SimulationModel) {}
    func start() {}
    func stop() {}
}

#endif
