# bend-toon (vendored)

TOON (spec v3.3) encoder and decoder for Bend 2, copied unchanged from
https://github.com/davidawad/bend-toon at commit

    9799b2c5fc455ff950db13e0923110bfa1fc7e47   (release-prep tip: just ci green, 389/389 spec conformance)

Files: `main.bend`, `src/`, `LICENSE`, `.bend-version`. The README, tests,
the conformance fixtures and the proofs stay in the upstream repo; do not edit
anything here, change upstream and re-vendor.

Re-vendor: `git -C <bend-toon checkout> archive <sha> main.bend src LICENSE .bend-version | tar -x -C vendor/bend-toon`, then update the sha above.

## Switch-over once bend-toon is published to BendHub

When bend-toon is on BendHub, replace `import ../../vendor/bend-toon/main.bend as Toon` in `src/fmt/toon.bend` with `import bend-toon@0.1.0.0/main.bend as Toon` and delete this directory.
