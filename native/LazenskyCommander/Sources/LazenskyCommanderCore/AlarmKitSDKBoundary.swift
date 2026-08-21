// LazenskyCommanderCore stays platform-neutral and must compile without AlarmKit.
// The concrete iOS 26 implementation lives in
// native/LazenskyCommanderApp/LazenskyCommanderApp/AlarmKitAdapter.swift.
// Keep UnavailableAlarmKitAdapter available for CoreCheck and non-iOS test environments.
