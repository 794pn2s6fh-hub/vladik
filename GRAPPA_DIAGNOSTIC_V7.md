# v7 Grappa linkage diagnostics

This revision is intentionally diagnostic-only. It does not change the Airlift exploit implementation.

It adds:

- a `GrappaHelper.m` load marker (`Erosion: GrappaHelper.m loaded`), proving the Objective-C source is present in the app image at runtime;
- a CI script at `scripts/verify_grappa_build.sh` that inspects the final `Erosion.app/Erosion` binary for `ALGetGrappaToken` after the IPA is built;
- a GitHub Actions step that runs the inspection automatically.

Interpretation:

1. If `GrappaHelper.m: present` but the final binary has no `ALGetGrappaToken` symbol mention, the source was not retained/exported into the final image.
2. If the symbol is present but the runtime log still reports `symbol not found`, the discrepancy is at runtime symbol visibility/loading rather than source inclusion.
3. If the marker never appears in app logs, the Objective-C source is not being loaded into the running image.

The diagnostics do not invoke AirTraffic, Grappa, or any sandbox-escape operation.
