import Darwin
import Foundation
import IOKit

enum HardwareMetrics {
    static func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var values: [Double] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard let property = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let stats = property as? [String: Any] else { continue }
            if let number = stats["Device Utilization %"] as? NSNumber {
                values.append(number.doubleValue)
            }
        }
        return values.max().map { min(max($0, 0), 100) }
    }

    static func cpuTemperatureCelsius() -> Double? {
        guard let fns = HIDFunctions.shared, let client = hidClient else { return nil }
        guard let unmanaged = fns.copyServices(client) else { return nil }
        let services = unmanaged.takeRetainedValue() as Array
        var readings: [Double] = []

        for raw in services {
            let service: HIDService = unsafeBitCast(raw as AnyObject, to: HIDService.self)
            guard let productRef = fns.copyProperty(service, "Product" as CFString) else { continue }
            let product = productRef.takeRetainedValue() as? String ?? ""
            guard product.localizedCaseInsensitiveContains("PMU tdie") ||
                    product.localizedCaseInsensitiveContains("pACC MTR") ||
                    product.localizedCaseInsensitiveContains("eACC MTR") else { continue }
            guard let eventRef = fns.copyEvent(service, 15, 0, 0) else { continue }
            let event = eventRef.takeRetainedValue()
            let value = withExtendedLifetime(event) {
                fns.getFloatValue(unsafeBitCast(event, to: HIDEvent.self), Int32(15 << 16))
            }
            if value > 0, value < 150 { readings.append(value) }
        }
        return readings.max()
    }

    private static let hidClient: HIDClient? = {
        guard let fns = HIDFunctions.shared, let client = fns.create(kCFAllocatorDefault) else { return nil }
        let match: [String: Any] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 0x0005]
        _ = fns.setMatching(client, match as CFDictionary)
        return client
    }()
}

private typealias HIDClient = OpaquePointer
private typealias HIDService = OpaquePointer
private typealias HIDEvent = OpaquePointer
private typealias HIDCreate = @convention(c) (CFAllocator?) -> HIDClient?
private typealias HIDSetMatching = @convention(c) (HIDClient, CFDictionary?) -> Int32
private typealias HIDCopyServices = @convention(c) (HIDClient) -> Unmanaged<CFArray>?
private typealias HIDCopyEvent = @convention(c) (HIDService, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
private typealias HIDCopyProperty = @convention(c) (HIDService, CFString) -> Unmanaged<CFTypeRef>?
private typealias HIDGetFloatValue = @convention(c) (HIDEvent, Int32) -> Double

private struct HIDFunctions {
    let create: HIDCreate
    let setMatching: HIDSetMatching
    let copyServices: HIDCopyServices
    let copyEvent: HIDCopyEvent
    let copyProperty: HIDCopyProperty
    let getFloatValue: HIDGetFloatValue

    static let shared: HIDFunctions? = {
        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        func resolve<T>(_ name: String, as type: T.Type) -> T? {
            guard let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: type)
        }
        guard let create = resolve("IOHIDEventSystemClientCreate", as: HIDCreate.self),
              let setMatching = resolve("IOHIDEventSystemClientSetMatching", as: HIDSetMatching.self),
              let copyServices = resolve("IOHIDEventSystemClientCopyServices", as: HIDCopyServices.self),
              let copyEvent = resolve("IOHIDServiceClientCopyEvent", as: HIDCopyEvent.self),
              let copyProperty = resolve("IOHIDServiceClientCopyProperty", as: HIDCopyProperty.self),
              let getFloatValue = resolve("IOHIDEventGetFloatValue", as: HIDGetFloatValue.self) else { return nil }
        return HIDFunctions(create: create, setMatching: setMatching, copyServices: copyServices,
                            copyEvent: copyEvent, copyProperty: copyProperty, getFloatValue: getFloatValue)
    }()
}
