import Foundation

#if os(Linux)
    extension NSStringEncoding {
        static var utf8: NSStringEncoding {
            return NSStringEncoding(kCFStringEncodingUTF8)
        }
    }
    typealias JSONSerialization = NSJSONSerialization
#endif

extension ModelParser.FieldType {
    public var enumCaseName: String {
        switch self {
        case .object: return "object"
        case .list: return "list"
        case .text: return "text"
        case .number(.bool): return "boolean"
        case .number: return "number"
        case .enum: return "enum"
        case .unknown: return "unknownType"
        case let .optional(type): return type.enumCaseName
        }
    }
}


extension String {
    
    init(lines: String...) {
        self = lines.joined(separator: "\n")
    }
    
    init(joined parts: [String], separator: String = "\n") {
        self = parts.joined(separator: separator)
    }
    
    public func times(_ times: Int) -> String {
        return String(joined: (0..<times).lazy.map { _ -> String in
            return self
        }, separator: "")
    }
    
    public func indent(_ level: Int, spaces: Int = 4) -> String {
        let suffix = self.hasSuffix("\n") ? "\n" : ""
        let indented = String(joined: self.characters.split(separator: "\n").lazy.map { " ".times(level * spaces) + String($0) })
        return indented + suffix
    }
    public func firstCapitalized() -> String {
        if isEmpty { return "" }
        var result = self
        result.replaceSubrange(startIndex...startIndex, with: String(self[startIndex]).uppercased())
        return result
    }
    public func firstLowercased() -> String {
        if isEmpty { return "" }
        var result = self
        result.replaceSubrange(startIndex...startIndex, with: String(self[startIndex]).lowercased())
        return result
    }
    
    public func pascalCased() -> String {
        let slices = self.characters.split { $0 == "_" || $0 == " " }
        if let first = slices.first {
            return slices.dropFirst().reduce(String(first)) { (string, subSequence) in
                return string + String(subSequence[subSequence.startIndex]).uppercased() + String(subSequence.suffix(from: subSequence.index(subSequence.startIndex, offsetBy: 1)))
                }.firstLowercased()
        }
        return self
    }
    public var camelCasedString: String {
        return self.pascalCased().firstCapitalized()
    }
    
    
    static let swiftKeywords: Set<String> = [
        "class", "deinit", "enum", "extension", "func", "import", "init", "inout", "internal", "let", "operator", "private", "protocol", "public", "static", "struct", "subscript", "typealias", "var", "break", "case", "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while", "as", "catch", "dynamicType", "false", "is", "nil", "rethrows", "super", "self", "Self", "throw", "throws", "true", "try", "__COLUMN__", "__FILE__", "__FUNCTION__",  "__LINE__", "_", "associativity", "convenience", "dynamic", "didSet", "final", "get", "infix", "indirect", "lazy", "left", "mutating", "none", "nonmutating", "optional", "override", "postfix", "precedence", "prefix", "Protocol", "required", "right", "set", "Type", "unowned", "weak", "willSet"
    ]
    
    public var swiftKeywordEscaped: String {
        if String.swiftKeywords.contains(self) {
            return "`\(self)`"
        } else {
            return self
        }
    }
    
    
    public var asValidSwiftIdentifier: String {
        let chars = self.characters
        if let identifierHead = chars.first {
            let head: String
            let identifierTail = chars.suffix(from: chars.index(after: chars.startIndex))
            let tail = String(joined: identifierTail.split(whereSeparator: CharacterSet.swiftIdentifierValidTailChars.inverted.contains).map(String.init), separator: "_").pascalCased()
            if CharacterSet.swiftIdentifierValidHeadChars.contains(identifierHead) {
                head = String(identifierHead)
            } else {
                head = tail.isEmpty || !CharacterSet.swiftIdentifierValidHeadChars.contains(tail.characters.first!) ? "_" : ""
            }
            return "\(head)\(tail)"
        } else {
            return "_"
        }
    }
}

#if os(Linux)
    typealias CharacterSet = NSCharacterSet
    
    typealias ComparisonResult = NSComparisonResult
    
    extension CharacterSet {
        convenience init(charactersIn range: Range<UnicodeScalar>) {
            self.init(range: NSRange(location: Int(range.lowerBound.value), length: Int(range.upperBound.value - range.lowerBound.value)))
        }
        
        func contains(_ scalar: UnicodeScalar) -> Bool {
            return longCharacterIsMember(scalar.value)
        }
        
    }
#endif

extension CharacterSet {
    fileprivate static let swiftIdentifierValidHeadChars: CharacterSet = {
        let ranges: [CountableClosedRange<UInt32>] = [
            0xA8...0xA8,
            0xAA...0xAA,
            0xAD...0xAD,
            0xAF...0xAF,
            0xB2...0xB5,
            0xB7...0xBA,
            0xBC...0xBE,
            0xC0...0xD6,
            0xD8...0xF6,
            0xF8...0xFF,
            0x100...0x2FF,
            0x370...0x167F,
            0x1681...0x180D,
            0x180F...0x1DBF,
            0x1E00...0x1FFF,
            0x200B...0x200D,
            0x202A...0x202E,
            0x203F...0x2040,
            0x2054...0x2054,
            0x2060...0x206F,
            0x2070...0x20CF,
            0x2100...0x218F,
            0x2460...0x24FF,
            0x2776...0x2793,
            0x2C00...0x2DFF,
            0x2E80...0x2FFF,
            0x3004...0x3007,
            0x3021...0x302F,
            0x3031...0x303F,
            0x3040...0xD7FF,
            0xF900...0xFD3D,
            0xFD40...0xFDCF,
            0xFDF0...0xFE1F,
            0xFE30...0xFE44,
            0xFE47...0xFFFD,
            0x10000...0x1FFFD,
            0x20000...0x2FFFD,
            0x30000...0x3FFFD,
            0x40000...0x4FFFD,
            0x50000...0x5FFFD,
            0x60000...0x6FFFD,
            0x70000...0x7FFFD,
            0x80000...0x8FFFD,
            0x90000...0x9FFFD,
            0xA0000...0xAFFFD,
            0xB0000...0xBFFFD,
            0xC0000...0xCFFFD,
            0xD0000...0xDFFFD,
            0xE0000...0xEFFFD
        ]
        var charset = CharacterSet.uppercaseLetters
        charset.formUnion(.lowercaseLetters)
        charset.insert(charactersIn: "_")
        ranges.forEach {
            charset.formUnion(CharacterSet(charactersIn: UnicodeScalar($0.lowerBound)!..<UnicodeScalar($0.upperBound)!))
            
        }
        return charset
    }()
    
    fileprivate static let swiftIdentifierValidTailChars: CharacterSet = {
        let ranges: [CountableClosedRange<UInt32>] = [
            0x300...0x36F,
            0x1DC0...0x1DFF,
            0x20D0...0x20FF,
            0xFE20...0xFE2F,
        ]
        var charset = CharacterSet.decimalDigits
        charset.formUnion(.swiftIdentifierValidHeadChars)
        ranges.forEach {
            charset.formUnion(CharacterSet(charactersIn: UnicodeScalar($0.lowerBound)!..<UnicodeScalar($0.upperBound)!))
        }
        return charset
    }()
    
    func contains(_ char: Character) -> Bool {
        for codeUnit in String(char).utf16 {
            if !contains(UnicodeScalar(codeUnit)!) {
                return false
            }
        }
        return true
    }
    
}
