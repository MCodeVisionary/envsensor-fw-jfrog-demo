/*
 * Dummy placeholder — NOT real SQLite source.
 *
 * Exists only so scripts/xray_scan.sh can declare a dependency on
 * sqlite3:299.1.0.8 in the generated Xray build-info, matching the
 * component ID used in JFrog's public C/C++ Xray scanning reference:
 * https://github.com/MaharshiPatel/helloworld
 *
 * Unlike third_party/zlib-1.2.11 and third_party/ffmpeg-n6.1, this file is
 * fabricated, not genuine vendored upstream code — see third_party/README.md.
 * It is never compiled into envsensor_fw.
 */
int envsensor_fw_sqlite3_stub_marker(void) {
    return 0;
}
