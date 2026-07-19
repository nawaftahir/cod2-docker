# Server binaries

Vendored `cod2_lnxded` dedicated server binaries, selectable at runtime via
`COD2_VERSION` and `COD2_VARIANT` (see [docs/configuration.md](../docs/configuration.md)).

## Variant matrix

| Binary | Version | Notes |
|---|---|---|
| `cod2_lnxded_1_0a` | 1.0 | plain |
| `cod2_lnxded_1_0a_va` | 1.0 | va security patch |
| `cod2_lnxded_1_0a_va_loc` | 1.0 | va + no localization spam |
| `cod2_lnxded_1_2c` | 1.2 | plain |
| `cod2_lnxded_1_2c_nodelay` | 1.2 | nodelay |
| `cod2_lnxded_1_2c_nodelay_va_loc` | 1.2 | nodelay + va + loc |
| `cod2_lnxded_1_2c_patch_va_loc` | 1.2 | va + loc |
| `cod2_lnxded_1_3` | 1.3 | plain (default) |
| `cod2_lnxded_1_3_cracked` | 1.3 | no CD-key check, master server disabled, nodelay |
| `cod2_lnxded_1_3_nodelay` | 1.3 | nodelay |
| `cod2_lnxded_1_3_nodelay_va_loc` | 1.3 | nodelay + va + loc (recommended) |
| `cod2_lnxded_1_3_patch_va_loc` | 1.3 | va + loc |

## Suffix meanings

- `nodelay` - lowers the required master-server offline time before reconnect (~30 min to 5 s)
- `cracked` - disables the master server + CD-key check, includes nodelay
- `loc` - suppresses non-localized string console spam
- `va` - patches a string overrun in `va()` (>1024 chars); a security fix, recommended

Binary patches by **Kung Foo Man** and **Mitch** (Killtube).
