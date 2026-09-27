import Foundation

/// C-compatible callback for Airlift logging.
/// C function pointers cannot capture Swift context, so this is a
/// file-independent callback used by the AirCard feature writers.
func erosionAirCardCLogCallback(_ ctx: UnsafeMutableRawPointer?, _ msg: UnsafePointer<CChar>?) {
    guard let msg else { return }
    print("[Airlift] \(String(cString: msg))")
}
