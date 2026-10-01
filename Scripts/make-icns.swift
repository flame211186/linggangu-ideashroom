import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("usage: make-icns.swift <iconset-directory> <output.icns>\n".utf8)
    )
    exit(2)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let chunks: [(type: String, filename: String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func bigEndianData(_ value: UInt32) -> Data {
    var encoded = value.bigEndian
    return withUnsafeBytes(of: &encoded) { Data($0) }
}

var payload = Data()
for chunk in chunks {
    let pngURL = iconsetURL.appendingPathComponent(chunk.filename)
    let png = try Data(contentsOf: pngURL)
    guard let type = chunk.type.data(using: .ascii), type.count == 4 else {
        throw CocoaError(.fileReadCorruptFile)
    }
    payload.append(type)
    payload.append(bigEndianData(UInt32(png.count + 8)))
    payload.append(png)
}

var file = Data("icns".utf8)
file.append(bigEndianData(UInt32(payload.count + 8)))
file.append(payload)
try file.write(to: outputURL, options: .atomic)
print(outputURL.path)
