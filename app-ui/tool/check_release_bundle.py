#!/usr/bin/env python3
"""Release bundle check: run on an .aab before uploading it to Google Play.

    python3 app-ui/tool/check_release_bundle.py [options] BUNDLE.aab

Reads only the bundle itself and prints its versionName, versionCode,
targetSdk, signer, permissions and native libraries. Then it applies the
release rules from issue #20.

Exit codes: 0 every rule passed, 1 a rule failed, 2 the check could not run
(bad arguments, missing tools, unreadable bundle).

Needs Python 3.8+, a JDK (keytool, jarsigner on PATH or under JAVA_HOME) and
the Android SDK build tools (aapt2, found under ANDROID_HOME or
ANDROID_SDK_ROOT, or pass --aapt2). It needs nothing else: aapt2 reads the
bundle's protobuf manifest directly.
"""

import argparse
import glob
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

# The applicationId Play Console's app is locked to.
PACKAGE_NAME = "io.adambailey.humspan"

# Play's minimum target API for new apps and updates (API 36 since 31 Aug 2026).
# Raise it when Play raises its rule; check Play Console on the day.
MIN_TARGET_SDK = 36

# The permissions the release may declare (issue #20). Adding one means updating
# this list, the Play Data safety form and the privacy policy in the same change.
# WAKE_LOCK comes from a dependency; the app itself holds no wake lock.
ALLOWED_PERMISSIONS = frozenset([
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.WAKE_LOCK",
    "android.permission.ACCESS_NETWORK_STATE",
    # AndroidX declares this signature permission under the app's own package.
    f"{PACKAGE_NAME}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION",
])

# Never allowed: the "no data collected or shared" Data safety answer depends on it.
FORBIDDEN_PERMISSIONS = frozenset(["android.permission.INTERNET"])

# Play wants signing certificates valid until after this date (strict mode).
SIGNER_VALID_AFTER = (2033, 10, 22)

# Play requires every 64-bit native library to load on 16 KB page devices: each
# ELF LOAD segment aligned to at least 16 KB (64 KB also works). 32-bit ABIs run
# only on 4 KB page devices, so their alignment is reported but not enforced.
MIN_LOAD_ALIGN = 0x4000
ALIGN_ENFORCED_ABIS = frozenset(["arm64-v8a", "x86_64"])

RULE_FAILED = 1
CANNOT_RUN = 2


class CheckError(Exception):
    """The check could not run. Exit code 2."""


# --- tools -------------------------------------------------------------------

def find_sdk():
    for var in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        if os.environ.get(var) and os.path.isdir(os.environ[var]):
            return os.environ[var]
    for guess in ("~/Library/Android/sdk", "~/Android/Sdk"):
        path = os.path.expanduser(guess)
        if os.path.isdir(path):
            return path
    return None


def _version_key(name):
    return [int(p) if p.isdigit() else -1 for p in name.replace("-", ".").split(".")]


def find_aapt2(explicit):
    if explicit:
        if not os.path.isfile(explicit):
            raise CheckError("--aapt2 %s: no such file" % explicit)
        return explicit
    sdk = find_sdk()
    if sdk:
        found = glob.glob(os.path.join(sdk, "build-tools", "*", "aapt2"))
        if found:
            return max(found, key=lambda p: _version_key(os.path.basename(os.path.dirname(p))))
    on_path = shutil.which("aapt2")
    if on_path:
        return on_path
    raise CheckError(
        "aapt2 not found. Install the Android SDK build tools "
        "(sdkmanager 'build-tools;36.0.0'), set ANDROID_HOME, or pass --aapt2 PATH.")


def java_tool(name):
    java_home = os.environ.get("JAVA_HOME")
    if java_home:
        path = os.path.join(java_home, "bin", name)
        if os.path.isfile(path):
            return path
    on_path = shutil.which(name)
    if on_path:
        return on_path
    raise CheckError("%s not found. Install a JDK and put it on PATH or set JAVA_HOME." % name)


def run(cmd):
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          universal_newlines=True)
    return proc.returncode, proc.stdout


# --- reading the bundle --------------------------------------------------------

def read_manifest(aab, aapt2):
    """Returns (facts, permissions): facts from the base module's manifest, and
    the permissions every module's manifest declares."""
    try:
        with zipfile.ZipFile(aab) as src:
            names = src.namelist()
            if "base/manifest/AndroidManifest.xml" not in names:
                raise CheckError("%s is not an Android App Bundle with a base module" % aab)
            # <module>/manifest/AndroidManifest.xml, base first.
            modules = ["base"] + sorted(
                n.split("/")[0] for n in names
                if n.endswith("/manifest/AndroidManifest.xml") and n.count("/") == 2
                and not n.startswith("base/"))
            dumps = [_dump_badging(src, module, aapt2) for module in modules]
    except zipfile.BadZipFile as e:
        raise CheckError("%s is not an Android App Bundle (%s)" % (aab, e))

    facts = {}
    permissions = []
    for module, out in zip(modules, dumps):
        for line in out.splitlines():
            if line.startswith("package:") and module == "base":
                for field in ("name", "versionCode", "versionName"):
                    facts[field] = _quoted(line, field)
            elif line.startswith("targetSdkVersion:") and module == "base":
                facts["targetSdk"] = line.split(":", 1)[1].strip().strip("'")
            elif line.startswith(("uses-permission:", "uses-permission-sdk-23:")):
                name = _quoted(line, "name")
                if name and name not in permissions:
                    permissions.append(name)
    return facts, permissions


def _dump_badging(src, module, aapt2):
    """aapt2's badging dump of one module's manifest."""
    with tempfile.TemporaryDirectory(prefix="humspan-aab-") as tmp:
        # aapt2 reads a proto-format "APK": manifest (and resources.pb) at the root.
        proto = os.path.join(tmp, module + ".zip")
        with zipfile.ZipFile(proto, "w") as out:
            out.writestr("AndroidManifest.xml",
                         src.read(module + "/manifest/AndroidManifest.xml"))
            if module + "/resources.pb" in src.namelist():
                out.writestr("resources.pb", src.read(module + "/resources.pb"))
        code, out = run([aapt2, "dump", "badging", proto])
    if code != 0:
        raise CheckError("aapt2 could not read the %s module's manifest:\n%s" % (module, out))
    return out


def _quoted(line, field):
    marker = " %s='" % field
    start = line.find(marker)
    if start < 0:
        marker = "%s='" % field
        start = line.find(marker)
        if start < 0:
            return None
    start += len(marker)
    return line[start:line.index("'", start)]


def load_alignments(elf):
    """The p_align of each PT_LOAD segment in an ELF image, or None if the bytes
    are not a readable ELF file."""
    if len(elf) < 52 or elf[:4] != b"\x7fELF" or elf[4] not in (1, 2) or elf[5] not in (1, 2):
        return None
    is64 = elf[4] == 2
    end = "<" if elf[5] == 1 else ">"
    try:
        if is64:
            phoff, = struct.unpack_from(end + "Q", elf, 32)
            phentsize, phnum = struct.unpack_from(end + "HH", elf, 54)
        else:
            phoff, = struct.unpack_from(end + "I", elf, 28)
            phentsize, phnum = struct.unpack_from(end + "HH", elf, 42)
        aligns = []
        for i in range(phnum):
            at = phoff + i * phentsize
            p_type, = struct.unpack_from(end + "I", elf, at)
            if p_type != 1:  # PT_LOAD
                continue
            if is64:
                p_align, = struct.unpack_from(end + "Q", elf, at + 48)
            else:
                p_align, = struct.unpack_from(end + "I", elf, at + 28)
            aligns.append(p_align)
        return aligns
    except struct.error:
        return None


def read_native_libs(aab):
    """[(path inside the bundle, ABI, LOAD alignments or None)] for every .so in
    every module."""
    libs = []
    with zipfile.ZipFile(aab) as z:
        for name in sorted(z.namelist()):
            parts = name.split("/")
            # <module>/lib/<abi>/<name>.so
            if len(parts) == 4 and parts[1] == "lib" and parts[3].endswith(".so"):
                libs.append((name, parts[2], load_alignments(z.read(name))))
    return libs


def read_signer(aab):
    """Returns the first signer's certificate owner, SHA-256 and 'until' date."""
    code, out = run([java_tool("keytool"), "-J-Duser.language=en", "-J-Duser.country=US",
                     "-printcert", "-jarfile", aab])
    if code != 0:
        # An unsigned bundle exits 0 ("Not a signed jar file"); this is keytool failing.
        raise CheckError("keytool could not read the bundle's signer:\n" + out)
    signer = {"owner": None, "sha256": None, "until": None}
    for raw in out.splitlines():
        line = raw.strip()
        if line.startswith("Owner:") and signer["owner"] is None:
            signer["owner"] = line[len("Owner:"):].strip()
        elif line.startswith("SHA256:") and signer["sha256"] is None:
            signer["sha256"] = line[len("SHA256:"):].strip()
        elif line.startswith("Valid from:") and signer["until"] is None and " until: " in line:
            signer["until"] = line.split(" until: ", 1)[1].strip()
    return signer


def signature_verifies(aab):
    code, out = run([java_tool("jarsigner"), "-verify", aab])
    return code == 0 and "jar verified." in out


# --- rules ---------------------------------------------------------------------

def _until_date(until):
    """'Fri Nov 19 18:31:19 PST 2027' (keytool, en_US) -> (2027, 11, 19), or None."""
    parts = until.split() if until else []
    if len(parts) < 6 or parts[1] not in _MONTHS or not parts[-1].isdigit():
        return None
    return (int(parts[-1]), _MONTHS.index(parts[1]) + 1, int(parts[2]))


_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
           "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def check_signer(signer, verified, strict):
    """Both modes reject an unsigned bundle and the debug key. Strict mode also
    wants a long-lived key, which a CI throwaway key is not."""
    if not signer["owner"] or not verified:
        return ["bundle is unsigned or its signature does not verify (jarsigner -verify)"]
    if "CN=Android Debug" in signer["owner"]:
        return ["signed with the Android debug certificate (%s); sign with the upload key"
                % signer["owner"]]
    if strict:
        until = _until_date(signer["until"])
        if until is None:
            return ["could not read the signing certificate's expiry (%s)" % signer["until"]]
        if until <= SIGNER_VALID_AFTER:
            return ["signing certificate expires %s; Play wants keys valid after %04d-%02d-%02d"
                    " (is this a throwaway key?)" % ((signer["until"],) + SIGNER_VALID_AFTER)]
    return []


def check_package(package):
    if package != PACKAGE_NAME:
        return ["package %s is not the Play app's %s; set applicationId" % (package, PACKAGE_NAME)]
    return []


def check_version_code(version_code, last):
    if version_code is None or not version_code.isdigit():
        return ["no numeric versionCode in the manifest (%s)" % version_code]
    if last is not None and int(version_code) <= last:
        return ["versionCode %s is not greater than the last upload's %d; raise the number"
                " after '+' in pubspec.yaml" % (version_code, last)]
    return []


def check_target_sdk(target_sdk):
    if target_sdk is None or not target_sdk.isdigit():
        return ["no numeric targetSdk in the manifest (%s)" % target_sdk]
    if int(target_sdk) < MIN_TARGET_SDK:
        return ["targetSdk %s is below Play's minimum %d; raise targetSdkVersion"
                % (target_sdk, MIN_TARGET_SDK)]
    return []


def alignment_enforced(abi):
    """Whether Play's 16 KB page rule applies to this ABI's libraries."""
    return abi in ALIGN_ENFORCED_ABIS


def check_native_libs(libs):
    problems = []
    for name, abi, aligns in libs:
        if not alignment_enforced(abi):
            continue
        if not aligns:
            problems.append("%s is not an ELF file with LOAD segments" % name)
            continue
        low = min(aligns)
        if low < MIN_LOAD_ALIGN:
            problems.append("%s has a LOAD segment aligned to %#x; 16 KB pages need %#x"
                            " (link with NDK r28+ or -Wl,-z,max-page-size=16384)"
                            % (name, low, MIN_LOAD_ALIGN))
    return problems


def check_permissions(permissions):
    problems = []
    for p in permissions:
        if p in FORBIDDEN_PERMISSIONS:
            problems.append("%s is forbidden (the Data safety answer relies on no network)" % p)
        elif p not in ALLOWED_PERMISSIONS:
            problems.append("%s is not in the allowlist; adding it also means updating the"
                            " Data safety form and the privacy policy" % p)
    return problems


# --- main ----------------------------------------------------------------------

def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Check an Android App Bundle against Humspan's Play release rules.",
        epilog="Exit 0: all rules passed. 1: a rule failed. 2: the check could not run.")
    parser.add_argument("bundle", help="path to the .aab to check")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--strict", dest="strict", action="store_true", default=True,
                      help="the owner's pre-upload check (default)")
    mode.add_argument("--non-strict", dest="strict", action="store_false",
                      help="accept any verified non-debug key (CI's throwaway key)")
    parser.add_argument("--last-version-code", metavar="N", type=int,
                        help="versionCode of the last upload to Play; the bundle's must be greater")
    parser.add_argument("--aapt2", metavar="PATH",
                        help="aapt2 to use (default: newest under $ANDROID_HOME/build-tools)")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    try:
        return _check(args)
    except CheckError as e:
        print("error: %s" % e, file=sys.stderr)
    except Exception as e:  # a crash is "could not run", never "a rule failed"
        print("error: the check crashed: %s: %s" % (type(e).__name__, e), file=sys.stderr)
    return CANNOT_RUN


def _check(args):
    if not os.path.isfile(args.bundle):
        raise CheckError("%s: no such file" % args.bundle)
    aapt2 = find_aapt2(args.aapt2)
    facts, permissions = read_manifest(args.bundle, aapt2)
    signer = read_signer(args.bundle)
    verified = signature_verifies(args.bundle)
    libs = read_native_libs(args.bundle)

    problems = []
    problems += check_signer(signer, verified, args.strict)
    problems += check_package(facts.get("name"))
    problems += check_version_code(facts.get("versionCode"), args.last_version_code)
    problems += check_target_sdk(facts.get("targetSdk"))
    problems += check_permissions(permissions)
    problems += check_native_libs(libs)

    print("bundle: %s" % args.bundle)
    print("package: %s" % facts.get("name"))
    print("versionName: %s" % facts.get("versionName"))
    print("versionCode: %s" % facts.get("versionCode"))
    print("targetSdk: %s" % facts.get("targetSdk"))
    print("signer: %s" % (signer["owner"] or "(unsigned)"))
    if signer["owner"]:
        print("signer SHA-256: %s" % signer["sha256"])
        print("signer valid until: %s" % signer["until"])
    print("permissions:")
    for p in permissions:
        print("  %s" % p)

    print("native libraries (LOAD alignment):")
    for name, abi, aligns in libs:
        shown = " ".join("%#x" % a for a in sorted(set(aligns))) if aligns else "(not ELF)"
        note = "" if alignment_enforced(abi) else "  (not checked)"
        print("  %s %s%s" % (name, shown, note))
    if not libs:
        print("  (none)")

    print("mode: %s" % ("strict" if args.strict else "non-strict"))
    if problems:
        print("\nFAILED: %d rule(s)" % len(problems))
        for p in problems:
            print("  - %s" % p)
        return RULE_FAILED
    print("\nOK: the bundle passes every release rule")
    return 0


if __name__ == "__main__":
    sys.exit(main())
