# filza2k

Standalone injected payload project for Filza.

## Behavior
- Exposes a fixed writable token slot in the binary (`gFilza2KTokenSlot`, size `2048` bytes).
- On every dylib load (`constructor`), checks if the slot is patched.
- If patched, calls `sandbox_extension_consume`.
- Keeps the handle alive while loaded and releases it on unload (`destructor`).

## Token marker
The app patches this marker in the dylib before injection:
- `SL2K_TOKEN_SLOT_V1`

## Build
```sh
cd filza2k
make
```

Output:
- `filza2k/build/Filza2KPayload.dylib`

## Patching flow (from symlin2k)
1. Build/copy `Filza2KPayload.dylib` to a writable location.
2. Patch the marker slot with a valid sandbox token.
3. Inject the patched dylib into Filza.
