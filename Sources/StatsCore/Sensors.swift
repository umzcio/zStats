import Foundation

public enum SMCDecoder {
    public static func value(type: String, bytes: [UInt8]) -> Double? {
        let value: Double
        switch type {
        case "flt ":
            guard bytes.count == 4 else { return nil }
            let bits = bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
            value = Double(Float(bitPattern: bits))
        case "ui8 ", "ui16", "ui32":
            let size = type == "ui8 " ? 1 : type == "ui16" ? 2 : 4
            guard bytes.count == size else { return nil }
            value = Double(bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        default:
            let chars = Array(type)
            guard bytes.count == 2, chars.count == 4,
                  type.hasPrefix("sp") || type.hasPrefix("fp"),
                  let integerBits = Int(String(chars[2]), radix: 16),
                  let fractionBits = Int(String(chars[3]), radix: 16),
                  integerBits + fractionBits == (type.hasPrefix("sp") ? 15 : 16) else { return nil }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            value = (type.hasPrefix("sp") ? Double(Int16(bitPattern: raw)) : Double(raw)) / pow(2, Double(fractionBits))
        }
        return value.isFinite ? value : nil
    }
}

public struct SensorReading: Identifiable, Sendable {
    public enum Kind: String, Sendable { case temperature, fan }
    public enum Group: String, CaseIterable, Sendable { case cpu = "CPU", gpu = "GPU", battery = "Battery", other = "Other temperatures", fan = "Fans" }
    public var id: String
    public var name: String
    public var kind: Kind
    public var group: Group
    public var value: Double?
    public init(id: String, name: String, kind: Kind = .temperature, group: Group = .other, value: Double?) {
        self.id = id; self.name = name; self.kind = kind; self.group = group
        self.value = value.flatMap { Self.valid($0, kind: kind) ? $0 : nil }
    }
    public static func valid(_ value: Double, kind: Kind) -> Bool {
        value.isFinite && (kind == .temperature ? value > 0 && value <= 130 : value >= 0 && value <= 20000)
    }
    public static func average(_ sensors: [Self], group: Group) -> Double? {
        let values = sensors.filter { $0.group == group && $0.kind == .temperature }.compactMap(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
