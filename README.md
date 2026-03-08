# filzasbx

Minimal injected payload for Filza:

- Exposes a fixed token slot in the dylib: `gFilzaSbxTokenSlot` (`2048` bytes)
- On dylib load (`constructor`), calls `sandbox_extension_consume(token)`
- Keeps the consume handle alive for process lifetime
- Releases handle on unload (`destructor`)

## Marker and patching

The slot is initialized with:

`FILZASBX_TOKEN_SLOT_V1`

Before injection, patch that marker bytes in the dylib with a NUL-terminated sandbox extension token.

Notes:
- Keep replacement length `< 2048` bytes including `\0`
- Newline at end of token is trimmed at runtime

## Build

```sh
make
```

Output:

- `build/filzasbx.dylib`

## Runtime result

If the token is valid and consumed successfully, Filza gets whatever access that token grants for that process session.
