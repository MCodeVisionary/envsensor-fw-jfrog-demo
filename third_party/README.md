# third_party/ — intentionally unmanaged dependencies

This directory exists to make a point, not just to add functionality: it's
code copied directly from two real, well-known open-source projects,
dropped into the repo the way an engineer under deadline pressure actually
does it — no package manager, no version pin beyond a directory name, no
license review. This is exactly the failure mode **JFrog Snippet
Detection** exists to catch: code whose origin, license, and CVE exposure
are invisible to a normal code review because nothing about it looks
different from code the team wrote itself.

Both are verbatim, unmodified upstream source (copyright headers intact).

## `zlib-1.2.11/`

Real files from [zlib 1.2.11](https://github.com/madler/zlib/tree/v1.2.11)
(`zlib.h`, `zconf.h`, `zutil.h`, `crc32.h`, `crc32.c`). zlib's license is
permissive (zlib License) but does require the origin not be misrepresented
— trivial to violate by accident once the files are three refactors removed
from however they got here.

**This one is actually wired into the build**: `src/interop_checksum.c`
calls zlib's `crc32()` to compute a checksum alongside the project's own
CRC-16 (`crc.h`), for interop with an external tool that expects zlib-style
CRC-32. That's the more common real-world case — copied code that made it
all the way into production, silently, without ever going through
dependency management or a curation gate.

zlib 1.2.11 also has a real, known vulnerability in a different file in the
same release (CVE-2018-25032, in `deflate.c`) — a concrete example of why
knowing *which version* of a copy-pasted library you're carrying matters
even when the specific function you copied isn't the vulnerable one.

## `ffmpeg-n6.1/`

`libavutil/crc.c` from [FFmpeg](https://github.com/FFmpeg/FFmpeg/blob/n6.1/libavutil/crc.c),
**LGPL-2.1-or-later** licensed at the file level — a copyleft license with
real source-disclosure obligations, unlike zlib's. **Not compiled** — it
depends on FFmpeg's internal build config and headers this project doesn't
vendor, and pulling those in just to compile an unused CRC function isn't
worth it for a demo. It sits here exactly as a lot of real vendored code
does: copied in for reference or a feature that never shipped, never
wired into the build, never removed — but still a license liability sitting
in version control, invisible unless something is specifically looking for
it (which is the entire point).

## `sqlite3-299.1.0.8/` and `poco-1.9.0.0/` — synthetic, not real vendored code

Unlike the two directories above, these each hold a single fabricated
placeholder `.c` file — not real SQLite or POCO source, and never compiled
into `envsensor_fw`. They exist only so `scripts/xray_scan.sh` can declare
`sqlite3:299.1.0.8` and `poco:1.9.0.0` as dependencies in the generated Xray
build-info, matching the exact component IDs used in JFrog's own C/C++ Xray
scanning walkthrough (https://github.com/MaharshiPatel/helloworld), which
are known to resolve to real CVE data in Xray's catalog — useful for a demo
scan that's guaranteed to surface findings without waiting on zlib/ffmpeg's
own CVE history.
