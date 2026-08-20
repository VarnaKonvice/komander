// This file is the only intentional SDK boundary. Do not add guessed AlarmKit API calls here.
// The current environment has Command Line Tools only, without Xcode or an iOS 26 SDK.
// On the first Xcode-based implementation, add the concrete AlarmAdapting implementation here
// after verifying the exact API signatures and entitlement/configuration requirements.
#if canImport(AlarmKit)
import AlarmKit
#endif
