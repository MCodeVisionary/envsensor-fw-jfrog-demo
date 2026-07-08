# envsensor-fw — JFrog for long-lifecycle embedded systems (demo)

A small embedded-C firmware project used to demonstrate how JFrog Artifactory
addresses three problems common to embedded programs with **10-40 year
support tails**:

1. **Reproducible builds** — the same commit rebuilds to a byte-identical
   binary, anywhere, so a device can be recertified or patched decades later
   without "it built differently this time."
2. **Pre-built object caching** — a shared compiled-object cache backed by
   Artifactory, so slow (often Windows-based) embedded dev workstations stop
   paying for the same compilation twice.
3. **Certification tracking** — signed, tamper-evident certification records
   cryptographically bound to a specific artifact's SHA-256, verifiable long
   after the CI system that produced them is gone.

It also speaks to the client's fourth requirement, **air-gapped delivery**:
everything here publishes into an ordinary Artifactory repository, which is
exactly what you'd promote through a release-bundle / offline-transfer flow
into a disconnected network — that promotion step isn't built out in this
demo, but the artifact + build-info + evidence model is the same at either
end of the air gap.

## Why this maps to the client's environment

| Client requirement | How this demo shows it |
| --- | --- |
| 10-40 year artifact lifecycle | Immutable local repo, checksum-addressed evidence, no dependency on CI history |
| Slow Windows-based builds | ccache pointed at an Artifactory-backed shared object cache (works identically on Windows) |
| Certification tracking | JFrog Evidence: signed DSSE envelope bound to the artifact digest |
| Reproducible builds | Pinned toolchain flags, `SOURCE_DATE_EPOCH`, path-independent debug info, verified by rebuilding twice |
| Air-gapped environments | Artifact + build-info + evidence all live in ordinary repos, ready for release-bundle export/import across the gap |

## Layout

```
CMakeLists.txt        Board-parameterized firmware build (BOARD_A / BOARD_B)
include/, src/         Firmware sources — sensor read, CRC framing, versioning
tests/                 Host-run unit test for the CRC module
repo-templates/        Artifactory repo definitions (generic-local x2)
evidence/              Certification predicate template
scripts/
  common.sh                    shared config, loads .env
  setup_artifactory.sh         one-time: creates repos, signing key, cache token
  artifactory_cache_proxy.py   local HTTP->HTTPS bridge (see note below)
  build.sh                     build + ccache + publish build-info
  certify.sh                   attach signed certification evidence
  verify_reproducible.sh       rebuild twice, diff checksums
```

## Prerequisites

- `cmake`, a C compiler (a real `arm-none-eabi-gcc` if you want actual
  cross-compiled firmware instead of the host-simulation fallback)
- `ccache` (`brew install ccache` / `apt install ccache` / Windows via
  scoop/choco)
- `jf` (JFrog CLI) already configured with a server — this demo targets
  server ID `mcodevisionaryorg` (edit `scripts/common.sh` to point elsewhere)
- `jq`

## Quick start

```sh
./scripts/setup_artifactory.sh          # one-time: repos + signing key + token
./scripts/build.sh BOARD_A              # build, cache, publish build-info
./scripts/certify.sh BOARD_A "Jane Doe" "Acme Certification Authority"
./scripts/verify_reproducible.sh BOARD_A
jf evd verify --subject-repo-path emb-airgap-demo-generic-local/envsensor-fw/BOARD_A/1.0.0/envsensor_fw \
  --use-artifactory-keys --server-id=mcodevisionaryorg
```

Repeat with `BOARD_B` for the second hardware variant sharing this codebase.

### Demo script: proving the cache is real

```sh
rm -rf build .ccache-local          # simulate a brand-new machine
./scripts/build.sh BOARD_A          # cold: mostly misses, populates Artifactory
rm -rf build .ccache-local          # wipe LOCAL cache again, remote is untouched
./scripts/build.sh BOARD_A          # now: hits served from Artifactory, not this disk
```

The second run's `ccache -s` output should show ~100% hits despite the local
cache directory being empty — the objects came from
`emb-airgap-demo-ccache-local`. This is the same mechanism a fleet of
Windows build machines would share.

## Notes on the ccache <-> Artifactory bridge

ccache's built-in HTTP remote-storage backend intentionally
[doesn't support HTTPS](https://ccache.dev/manual/latest.html#_http_storage_backend).
`scripts/artifactory_cache_proxy.py` is a small local process (Python
stdlib only, no dependencies) that speaks plain HTTP to ccache and HTTPS to
Artifactory, injecting the access token so it never appears in the
compiler's environment. This runs as a lightweight per-machine sidecar —
including on Windows build hosts.

If the build machine sits behind a TLS-inspecting corporate proxy (its root
CA is trusted by curl/`jf` via the OS keychain but not by Python's bundled
OpenSSL), set `CACHE_PROXY_CA_BUNDLE=/path/to/corp-root.pem`, or as a last
resort `CACHE_PROXY_INSECURE=1`.

## Reproducibility techniques used

- `SOURCE_DATE_EPOCH` (pinned to the last git commit time) instead of
  wall-clock `now()` for anything embedded in the binary.
- `-ffile-prefix-map` so `__FILE__`/debug info don't encode the absolute
  checkout path — two different clones at two different paths still produce
  identical bytes.
- No floating point, no platform intrinsics, no uninitialized reads in the
  synthetic sensor model — deterministic by construction.
- `scripts/verify_reproducible.sh` builds twice into independent directories
  and diffs SHA-256 to prove it, rather than just asserting it.

## Certification tracking

`scripts/certify.sh` fills `evidence/cert-template.json` with the artifact's
identity (build name/number, git commit, SHA-256) and a certifying
engineer/body, then signs it with `jf evd create-evidence` using the ECDSA
key `setup_artifactory.sh` generated. The public key is uploaded to the
platform's trusted keys, so `jf evd verify --use-artifactory-keys` can
confirm the certification independent of whoever holds the private key
today — the property that matters when the person who certified a board in
year 1 is unreachable by year 25. A parallel `jf rt set-props` call also
stamps quick-glance `cert.*` properties for UI/AQL filtering.

## CI/CD (GitHub Actions)

`.github/workflows/build.yml` runs on every push/PR: cmake build + ctest +
reproducibility check for both boards, no credentials required. On pushes to
`main` it goes further — authenticates to JFrog via **OIDC** (no static
platform token stored in GitHub at all), runs a security scan, then
publishes build-info, populates the shared cache, and attaches signed
certification evidence.

Authentication uses GitHub's OIDC identity federation: the workflow requests
a short-lived GitHub Actions ID token (`permissions: id-token: write`),
which JFrog exchanges for a scoped Artifactory access token via an identity
mapping configured on the platform (`github-docportal` provider, mapped to
this repo). Nothing long-lived is stored as a GitHub secret for platform
auth — only `EVIDENCE_SIGNING_KEY` (the certification signing key) remains a
static secret, since it's a cryptographic key, not a bearer credential to
the platform.

### Security scanning

`jf audit --secrets --sast --iac` runs in CI before publishing — the same
command caught a real finding during development (untrusted input reaching
an outgoing request in `artifactory_cache_proxy.py`, since fixed by
normalizing the path before forwarding it upstream) and flagged the local
`.env`/signing key as secrets when run against the working tree, which is
exactly why both are gitignored rather than committed.

Two Frogbot workflows are also included (`frogbot-scan-pull-request.yml`,
`frogbot-scan-repository.yml`), which is JFrog's documented path for
repo/PR-level scanning, including **JFrog Snippet Detection** — matching
code (including AI-generated code) against the JFrog Catalog to surface
license and CVE risk from copied/generated snippets. Snippet Detection
itself isn't a flag you pass to `jf audit`/`jf scan` (checked both the
CLI's current release and latest — no such flag exists yet); it's a
Catalog-matching capability that surfaces automatically in scan results
once the platform's entitlement (JFrog Unified Bundle) includes it, via
Xray/Frogbot rather than a standalone command.
