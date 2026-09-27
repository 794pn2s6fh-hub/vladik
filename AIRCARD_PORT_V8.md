# AirCard → Erosion v8

This revision ports AirCard-style feature/UI parity into Erosion while keeping the existing Erosion transport layer.

## Kept unchanged
- Pairing file handling in `Erosion/ErosionAirlift.swift`
- LocalDevVPN detection in `Erosion/AirliftNetworkStatus.swift`
- Existing `AirliftFFI` static library and C bridge

## Ported/expanded
- Wallet card scanner/list/artwork workflow
- Passcode theme import/preview
- Passcode Theme Creator (poster slice + individual keys)
- `.passthm` export
- TelephonyUI/language/bold target selectors
- `.tendies` import/preview/detection/apply UI already present in v7

The exploit/backend implementation itself is not modified by this port.
