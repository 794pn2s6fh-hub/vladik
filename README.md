# Erosion mod — Airlift build

This source keeps the existing Erosion tweaks, Supervision profile features and Airlift integration, and adds an AirCard-style customization layer inside **Tweaks → Experimental → Airlift**:

- Airlift — existing pairing + LocalDevVPN flow.
- Wallet Cards — scan Wallet-related syslog events, assign artwork, and flash selected card artwork through the existing Airlift FFI.
- Passcode Theme — import `.passthm`, preview keypad assets, and apply TelephonyUI cache artwork.
- Wallpapers (.tendies) — import/inspect `.tendies`, detect the PosterBoard container, inject descriptors, refresh PosterBoard state and request a device respring.

The new features reuse the existing Erosion pairing file and AirliftFFI instead of adding a second pairing implementation.

Build with the existing `ipabuild.sh` / GitHub Actions workflow.

- Passcode Theme Creator: poster slicing, individual-key editing, preview, export, and language/font target selectors.

Pairing and LocalDevVPN sources are intentionally left on the existing Erosion implementation. The bundled AirliftFFI/backend was not replaced or augmented by this port.
