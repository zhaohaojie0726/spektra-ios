# NOTICE

This repository is an independent Swift reimplementation of the
[spektrafilm](https://github.com/andreavolpato/spektrafilm) physical model by
Andrea Volpato. It is not affiliated with or endorsed by the upstream project.

## What comes from where

| Asset | Origin | License |
|---|---|---|
| Swift sources under `Swift/`, `App/` | written here, from the upstream model | **GPL-3.0-or-later** (derivative of spektrafilm) |
| `Swift/Sources/SpektraCore/Resources/profiles/*.json` | upstream spektrafilm | **CC BY-SA 4.0** (see `LICENSES/SPEKTRAFILM_LICENSE.txt`) |
| `Resources/packs/*` (baked constants, `tc_lut`, curves) | derived from the profiles above | **CC BY-SA 4.0** |
| `Resources/goldens/*` (test fixtures) | produced by running the upstream code | CC BY-SA 4.0 |
| Design notes under `docs/`, derived from reading the engine | — | same licence as the code |

Upstream statement, quoted from its README: the code is GPLv3 and "any derivative
work must also be open source under the same license"; the profiles and LUTs are
CC BY-SA 4.0 with an attribution requirement; the shipped LUT bundles carry a
separate "commercial use, free share, no resale" licence.

## What that means for this project

- **Personal use, sideloading, or publishing the source is fine.** The GPL
  obligations are satisfiable: keep this repository (including modifications)
  available under GPL-3.0.
- **Putting a build on the App Store is not covered by this licence.** GPL-3.0
  and the App Store terms conflict. If that is ever wanted, the upstream author
  offers to discuss alternatives — see the README of the upstream repository.
- **Attribution is required for the profiles.** Any build that ships them must
  carry the CC BY-SA notice and a link to the upstream project. `LICENSES/`
  holds the texts for that purpose.

## Credits

- Andrea Volpato — the spektrafilm model, data and reference implementation.
- [SpektraLab](https://github.com/JamesQiu2005/SpektraLab) — a macOS port whose
  documentation (and recorded traps) informed several decisions here. No code was
  copied from it.
- The CIE 1931 colour matching functions, the Hanatos 2025 spectral upsampling
  LUT, and the dichroic filter data come from the upstream project's own sources.
