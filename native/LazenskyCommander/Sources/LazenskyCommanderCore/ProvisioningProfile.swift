import Foundation

public struct ProvisioningProfileMetadata: Equatable, Sendable {
  public let creationDate: Date
  public let expirationDate: Date
  public let recommendedRefreshAt: Date

  public init?(creationDate: Date, expirationDate: Date) {
    guard creationDate.timeIntervalSince1970.isFinite, expirationDate.timeIntervalSince1970.isFinite,
          creationDate < expirationDate else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    guard let deadline = calendar.date(byAdding: .day, value: -1, to: expirationDate) else { return nil }
    self.creationDate = creationDate
    self.expirationDate = expirationDate
    self.recommendedRefreshAt = deadline
  }

  public static func readEmbeddedProfile(at url: URL?, bundleIdentifier: String) -> Self? {
    guard let url, let data = try? Data(contentsOf: url), data.count <= 1_048_576,
          let plist = ProvisioningCMS.propertyList(in: data) else { return nil }
    return decodePropertyList(plist, bundleIdentifier: bundleIdentifier)
  }

  public static func decodePropertyList(_ data: Data, bundleIdentifier: String) -> Self? {
    guard !bundleIdentifier.isEmpty,
          let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
          let profile = value as? [String: Any],
          let creation = profile["CreationDate"] as? Date,
          let expiration = profile["ExpirationDate"] as? Date,
          let entitlements = profile["Entitlements"] as? [String: Any],
          let appID = entitlements["application-identifier"] as? String,
          let separator = appID.firstIndex(of: ".") else { return nil }
    let suffix = String(appID[appID.index(after: separator)...])
    guard !appID[..<separator].isEmpty,
          suffix == bundleIdentifier || suffix == "*" ||
            (suffix.hasSuffix(".*") && bundleIdentifier.hasPrefix(String(suffix.dropLast()))) else { return nil }
    return Self(creationDate: creation, expirationDate: expiration)
  }
}

// Read only CMS SignedData's encapsulated plist, not arbitrary XML inside certificates.
// iOS validates the signed app/profile. This bounded DER reader extracts metadata; it
// does not replace signature verification. Unsupported encodings fail closed.
enum ProvisioningCMS {
  static func propertyList(in data: Data) -> Data? {
    guard data.count <= 1_048_576 else { return nil }
    let bytes = Array(data)
    var root = DERReader(bytes: bytes, range: 0..<bytes.count)
    guard var contentInfo = root.container(0x30), root.isAtEnd,
          contentInfo.value(0x06) == [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02],
          var wrapper = contentInfo.container(0xa0), contentInfo.isAtEnd,
          var signedData = wrapper.container(0x30), wrapper.isAtEnd,
          signedData.value(0x02) != nil,
          signedData.value(0x31) != nil,
          var encapsulated = signedData.container(0x30),
          encapsulated.value(0x06) == [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x01],
          var payload = encapsulated.container(0xa0), encapsulated.isAtEnd,
          let plist = payload.value(0x04), payload.isAtEnd else { return nil }
    return Data(plist)
  }

  private struct DERReader {
    let bytes: [UInt8]
    var range: Range<Int>
    var isAtEnd: Bool { range.isEmpty }

    mutating func container(_ tag: UInt8) -> Self? {
      guard let content = read(tag) else { return nil }
      return Self(bytes: bytes, range: content)
    }

    mutating func value(_ tag: UInt8) -> [UInt8]? {
      guard let content = read(tag) else { return nil }
      return Array(bytes[content])
    }

    private mutating func read(_ tag: UInt8) -> Range<Int>? {
      guard range.count >= 2, bytes[range.lowerBound] == tag else { return nil }
      var cursor = range.lowerBound + 1
      let firstLength = bytes[cursor]
      cursor += 1
      var length = Int(firstLength)
      if firstLength >= 0x80 {
        let count = Int(firstLength & 0x7f)
        guard (1...4).contains(count), count <= range.upperBound - cursor,
              bytes[cursor] != 0 else { return nil }
        length = 0
        for _ in 0..<count {
          length = length * 256 + Int(bytes[cursor])
          cursor += 1
        }
        guard length >= 128 else { return nil }
      }
      guard length <= range.upperBound - cursor else { return nil }
      let content = cursor..<(cursor + length)
      range = content.upperBound..<range.upperBound
      return content
    }
  }
}
