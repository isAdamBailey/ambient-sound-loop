#!/usr/bin/env python3
"""Self-test for check_release_bundle.py.

Builds small fixture bundles from scratch (aapt2 for the protobuf manifest, a
synthetic ELF for native code, keytool + jarsigner for the signature), runs the
check on each and asserts its exit code. A bad bundle must exit 1 (a rule
failed), not 2 (the check itself broke), so a crash never passes for a catch.

    python3 app-ui/tool/test_check_release_bundle.py

Needs the same tools as the check: Python 3.8+, a JDK (keytool, jarsigner) and
the Android SDK build tools (aapt2) plus one platform's android.jar.
"""

import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
CHECK = os.path.join(HERE, "check_release_bundle.py")
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
import check_release_bundle as crb  # noqa: E402  (finds the SDK, JDK and aapt2; MIN_TARGET_SDK)

# Written out, not crb.ALLOWED_PERMISSIONS: the test is a second source of truth.
GOOD_PERMISSIONS = [
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.WAKE_LOCK",
    "android.permission.ACCESS_NETWORK_STATE",
    "dev.humspan.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION",
]

failures = []


def find_android_jar():
    sdk = crb.find_sdk()
    platforms = os.path.join(sdk, "platforms") if sdk else None
    if not platforms or not os.path.isdir(platforms):
        sys.exit("self-test: no Android SDK platforms found (set ANDROID_HOME)")
    jars = [os.path.join(platforms, p, "android.jar") for p in os.listdir(platforms)]
    jars = [j for j in jars if os.path.isfile(j)]
    if not jars:
        sys.exit("self-test: no android.jar under " + platforms)
    return sorted(jars)[-1]


def elf64(align, load_segments=2):
    """A minimal little-endian ELF64 shared object with PT_LOAD headers."""
    phnum = load_segments
    header = struct.pack(
        "<4sBBBBB7sHHIQQQIHHHHHH",
        b"\x7fELF", 2, 1, 1, 0, 0, b"\0" * 7,
        3, 183, 1, 0, 64, 0, 0, 64, 56, phnum, 64, 0, 0,
    )
    phdrs = b"".join(
        struct.pack("<IIQQQQQQ", 1, 5, 0, 0, 0, 0x100, 0x100, align)
        for _ in range(phnum)
    )
    return header + phdrs


def elf32(align):
    """A minimal little-endian ELF32 shared object with one PT_LOAD header."""
    header = struct.pack(
        "<4sBBBBB7sHHIIIIIHHHHHH",
        b"\x7fELF", 1, 1, 1, 0, 0, b"\0" * 7,
        3, 40, 1, 0, 52, 0, 0, 52, 32, 1, 40, 0, 0,
    )
    phdr = struct.pack("<IIIIIIII", 1, 0, 0, 0, 0x100, 0x100, 5, align)
    return header + phdr


class Fixtures:
    def __init__(self, workdir):
        self.dir = workdir
        self.aapt2 = crb.find_aapt2(None)
        self.android_jar = find_android_jar()
        self.keystores = {}
        self.count = 0

    def keystore(self, dname, validity_days):
        key = (dname, validity_days)
        if key not in self.keystores:
            path = os.path.join(self.dir, "key%d.jks" % len(self.keystores))
            subprocess.run(
                [crb.java_tool("keytool"), "-genkeypair", "-keystore", path,
                 "-storepass", "fixture", "-keypass", "fixture", "-alias", "k",
                 "-keyalg", "RSA", "-keysize", "2048",
                 "-validity", str(validity_days), "-dname", dname, "-noprompt"],
                check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            self.keystores[key] = path
        return self.keystores[key]

    def bundle(self, version_code=2, version_name="1.0.0", target_sdk=crb.MIN_TARGET_SDK,
               permissions=GOOD_PERMISSIONS, sdk23_permissions=(), libs=None,
               signer="CN=Humspan Upload", validity_days=10000, signed=True,
               modules=None, corrupt_libs=False):
        """Writes a fixture .aab and returns its path. modules maps a feature
        module's name to the permissions its manifest declares. corrupt_libs
        damages the native libraries' bytes after signing."""
        if libs is None:
            libs = {"arm64-v8a/libhumspan.so": elf64(0x4000),
                    "x86_64/libhumspan.so": elf64(0x4000)}
        self.count += 1
        work = os.path.join(self.dir, "b%d" % self.count)
        os.makedirs(work)
        uses = "".join('<uses-permission android:name="%s"/>' % p for p in permissions)
        uses += "".join('<uses-permission-sdk-23 android:name="%s"/>' % p
                        for p in sdk23_permissions)
        proto = self.proto_manifest(work, "base",
            '<uses-sdk android:minSdkVersion="24" android:targetSdkVersion="%d"/>'
            '<permission android:name="dev.humspan.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"'
            ' android:protectionLevel="signature"/>%s' % (target_sdk, uses),
            ' android:versionCode="%d" android:versionName="%s"' % (version_code, version_name))
        aab = os.path.join(self.dir, "fixture%d.aab" % self.count)
        with zipfile.ZipFile(proto) as src, zipfile.ZipFile(aab, "w") as out:
            out.writestr("BundleConfig.pb", b"")
            out.writestr("base/manifest/AndroidManifest.xml", src.read("AndroidManifest.xml"))
            out.writestr("base/resources.pb", src.read("resources.pb"))
            for name, data in libs.items():
                out.writestr("base/lib/" + name, data)
            for module, module_permissions in (modules or {}).items():
                uses = "".join('<uses-permission android:name="%s"/>' % p
                               for p in module_permissions)
                # With no uses-sdk, aapt2 would report pre-API-4 implied permissions.
                feature = self.proto_manifest(
                    work, module, '<uses-sdk android:minSdkVersion="24"/>' + uses,
                    ' split="%s"' % module)
                with zipfile.ZipFile(feature) as fsrc:
                    out.writestr(module + "/manifest/AndroidManifest.xml",
                                 fsrc.read("AndroidManifest.xml"))
        if signed:
            keystore = self.keystore(signer, validity_days)
            subprocess.run(
                [crb.java_tool("jarsigner"), "-keystore", keystore, "-storepass", "fixture",
                 "-keypass", "fixture", aab, "k"],
                check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        if corrupt_libs:
            with open(aab, "rb") as f:
                raw = f.read()
            for data in libs.values():
                raw = raw.replace(data, data[:-1] + bytes([data[-1] ^ 0xFF]), 1)
            with open(aab, "wb") as f:
                f.write(raw)
        return aab

    def proto_manifest(self, work, module, body, attrs=""):
        """Links a manifest to protobuf format; returns the proto zip's path."""
        manifest = os.path.join(work, module + "-AndroidManifest.xml")
        with open(manifest, "w") as f:
            f.write('<manifest xmlns:android="http://schemas.android.com/apk/res/android"'
                    ' package="dev.humspan.app"%s>%s<application/></manifest>' % (attrs, body))
        proto = os.path.join(work, module + "-proto.zip")
        subprocess.run(
            [self.aapt2, "link", "--proto-format", "-o", proto, "--manifest", manifest,
             "-I", self.android_jar],
            check=True,
        )
        return proto

    def script(self, name, body, executable=True):
        """Writes a stand-in for a tool; returns its path."""
        path = os.path.join(self.dir, name)
        with open(path, "w") as f:
            f.write("#!/bin/sh\n" + body + "\n")
        os.chmod(path, 0o755 if executable else 0o644)
        return path

    def java_home_with_failing_keytool(self):
        """A JAVA_HOME whose keytool always fails and whose jarsigner is the real one."""
        home = os.path.join(self.dir, "broken-jdk")
        os.makedirs(os.path.join(home, "bin"))
        os.symlink(self.script("keytool", "echo 'keytool error: boom' >&2; exit 1"),
                   os.path.join(home, "bin", "keytool"))
        os.symlink(crb.java_tool("jarsigner"), os.path.join(home, "bin", "jarsigner"))
        return home


def run_check(aab, *args, env=None):
    proc = subprocess.run(
        [sys.executable, CHECK, *args, aab],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True,
        env=dict(os.environ, **(env or {})),
    )
    return proc.returncode, proc.stdout


def expect(name, aab, code, *args, contains=(), env=None):
    got, out = run_check(aab, *args, env=env)
    missing = [c for c in contains if c not in out]
    if got != code or missing:
        failures.append(name)
        print("FAIL %s: exit %d (want %d)%s\n%s" % (
            name, got, code,
            "; output lacks " + ", ".join(repr(m) for m in missing) if missing else "",
            "    " + out.replace("\n", "\n    ")))
    else:
        print("ok   " + name)


def main():
    workdir = tempfile.mkdtemp(prefix="humspan-bundle-check-")
    try:
        fx = Fixtures(workdir)
        good = fx.bundle(version_code=5, version_name="1.2.3")

        expect("good bundle passes in strict mode", good, 0,
               contains=["versionName: 1.2.3", "versionCode: 5",
                         "CN=Humspan Upload", "android.permission.WAKE_LOCK"])
        expect("good bundle passes in non-strict mode", good, 0, "--non-strict")

        debug = fx.bundle(signer="CN=Android Debug, O=Android, C=US")
        expect("debug-signed bundle fails in strict mode", debug, 1,
               contains=["Android Debug"])
        expect("debug-signed bundle fails in non-strict mode", debug, 1, "--non-strict")

        throwaway = fx.bundle(signer="CN=CI Throwaway", validity_days=30)
        expect("short-lived throwaway key passes in non-strict mode", throwaway, 0,
               "--non-strict")
        expect("short-lived throwaway key fails in strict mode", throwaway, 1,
               contains=["2033"])

        # good has versionCode 5
        expect("versionCode above the last upload passes", good, 0, "--last-version-code", "4")
        expect("versionCode equal to the last upload fails", good, 1,
               "--last-version-code", "5", contains=["versionCode"])
        expect("versionCode below the last upload fails", good, 1,
               "--non-strict", "--last-version-code", "9")

        extra = fx.bundle(permissions=GOOD_PERMISSIONS + ["android.permission.RECORD_AUDIO"])
        expect("permission outside the allowlist fails", extra, 1, "--non-strict",
               contains=["android.permission.RECORD_AUDIO"])
        internet = fx.bundle(permissions=GOOD_PERMISSIONS + ["android.permission.INTERNET"])
        expect("INTERNET fails", internet, 1, "--non-strict",
               contains=["android.permission.INTERNET"])
        internet23 = fx.bundle(sdk23_permissions=["android.permission.INTERNET"])
        expect("INTERNET via uses-permission-sdk-23 fails", internet23, 1, "--non-strict")
        fewer = fx.bundle(permissions=GOOD_PERMISSIONS[:2])
        expect("a subset of the allowlist passes", fewer, 0, "--non-strict")

        old_target = fx.bundle(target_sdk=crb.MIN_TARGET_SDK - 1)
        expect("targetSdk below the minimum fails", old_target, 1, "--non-strict",
               contains=["targetSdk"])

        page4k = fx.bundle(libs={"arm64-v8a/libhumspan.so": elf64(0x1000),
                                 "x86_64/libhumspan.so": elf64(0x4000)})
        expect("64-bit library aligned to 4 KB fails", page4k, 1, "--non-strict",
               contains=["arm64-v8a/libhumspan.so", "0x1000"])

        x86_4k = fx.bundle(libs={"arm64-v8a/libhumspan.so": elf64(0x4000),
                                 "x86_64/libhumspan.so": elf64(0x1000)})
        expect("x86_64 library aligned to 4 KB fails", x86_4k, 1, "--non-strict",
               contains=["x86_64/libhumspan.so"])
        page64k = fx.bundle(libs={"arm64-v8a/libhumspan.so": elf64(0x10000),
                                  "x86_64/libhumspan.so": elf64(0x10000)})
        expect("64 KB alignment passes", page64k, 0, "--non-strict")
        legacy32 = fx.bundle(libs={"arm64-v8a/libhumspan.so": elf64(0x4000),
                                   "armeabi-v7a/libhumspan.so": elf32(0x1000)})
        expect("32-bit library aligned to 4 KB is reported, not failed", legacy32, 0,
               "--non-strict", contains=["armeabi-v7a/libhumspan.so 0x1000  (not checked)"])
        not_elf = fx.bundle(libs={"arm64-v8a/libhumspan.so": b"not an ELF file"})
        expect("unreadable 64-bit library fails", not_elf, 1, "--non-strict",
               contains=["not an ELF"])

        unsigned = fx.bundle(signed=False)
        expect("unsigned bundle fails", unsigned, 1, "--non-strict", contains=["unsigned"])

        feature = fx.bundle(modules={"extras": ["android.permission.INTERNET"]})
        expect("INTERNET in a feature module's manifest fails", feature, 1, "--non-strict",
               contains=["android.permission.INTERNET"])
        feature_ok = fx.bundle(modules={"extras": GOOD_PERMISSIONS[:1]})
        expect("allowed permission in a feature module passes", feature_ok, 0, "--non-strict")

        # The check could not run: exit 2, never 1 (which would read as a rule failing).
        expect("failing keytool cannot run", good, 2, "--non-strict",
               env={"JAVA_HOME": fx.java_home_with_failing_keytool()},
               contains=["error:", "keytool"])
        unquoted = fx.script("aapt2-unquoted", "echo \"package: name='dev.humspan.app\"")
        expect("unterminated quote in aapt2 output cannot run", good, 2, "--non-strict",
               "--aapt2", unquoted, contains=["error:"])
        not_executable = fx.script("aapt2-not-executable", "exit 0", executable=False)
        expect("aapt2 that cannot be executed cannot run", good, 2, "--non-strict",
               "--aapt2", not_executable, contains=["error:"])
        corrupt = fx.bundle(corrupt_libs=True)
        expect("corrupt native library cannot run", corrupt, 2, "--non-strict",
               contains=["error:"])
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    if failures:
        print("\n%d self-test case(s) failed" % len(failures))
        return 1
    print("\nall self-test cases passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
