# Grappa symbol export fix

`GrappaHelper.m` implements `ALGetGrappaToken`, while the Rust core resolves that symbol with `dlsym(RTLD_DEFAULT, "ALGetGrappaToken")`.

The previous Xcode target used `-dead_strip`, so the helper function could be stripped because there was no ordinary link-time reference to it. The target now forces the symbol to be retained and exported with:

- `-Wl,-u,_ALGetGrappaToken`
- `-Wl,-exported_symbol,_ALGetGrappaToken`

Both Debug and Release configurations are updated.
