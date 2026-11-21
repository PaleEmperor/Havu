#!/usr/bin/env python3
"""Prepare the Android toolchain, build the APK, and install on one USB device.

Setup runs Google's SDK manager interactively. Local files and the debug key
live under .local-state. Installation preserves existing app data.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = 'studio.havu.illustration'
APK = ROOT / 'builds' / 'havu-beta.apk'
ANDROID_STATE = ROOT / '.local-state' / 'android'
LOCAL_SDK = ANDROID_STATE / 'sdk'
LOCAL_DATA = ANDROID_STATE / 'data'
LOCAL_CONFIG = ANDROID_STATE / 'config'
DEBUG_KEY = ANDROID_STATE / 'havu-debug.keystore'
ANDROID_TOOLS = 'commandlinetools-linux-15859902_latest.zip'
ANDROID_TOOLS_SHA = '4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583'
GODOT_TEMPLATE = 'Godot_v4.7.2-stable_android_debug.perfetto.apk'
GODOT_TEMPLATE_SHA = '7e480a90a763bbef7af2d9cc2873b094cc278d1ed26c13c0d2e72a36e4c815d0'
SDK_PACKAGES = ('platform-tools', 'build-tools;35.0.1', 'platforms;android-35')


def run(args, **kwargs):
    return subprocess.run([str(v) for v in args], check=True, **kwargs)


def configuration():
    godot = shutil.which(os.environ.get('HAVU_GODOT', 'godot'))
    if not godot:
        raise RuntimeError('Godot 4.7 was not found. Set HAVU_GODOT to its executable.')
    version = subprocess.check_output([godot, '--version'], text=True).strip()
    match = re.match(r'(\d+)\.(\d+)', version)
    if not match:
        raise RuntimeError('Could not read the Godot version.')
    config_root = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
    settings_file = config_root / 'godot' / f'editor_settings-{match[1]}.{match[2]}.tres'
    settings = settings_file.read_text() if settings_file.exists() else ''
    def setting(key):
        found = re.search(r'^' + re.escape(key) + r'\s*=\s*"([^"]*)"', settings, re.M)
        return found[1] if found else ''
    sdk_value = os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME')
    if not sdk_value:
        sdk_value = setting('export/android/android_sdk_path')
        if (LOCAL_SDK / 'platform-tools/adb').is_file():
            sdk_value = str(LOCAL_SDK)
    jdk_value = os.environ.get('JAVA_HOME') or setting('export/android/java_sdk_path')
    sdk = Path(sdk_value).expanduser() if sdk_value else Path.home() / 'Android' / 'Sdk'
    prism_jdk = (Path.home() / '.var/app/org.prismlauncher.PrismLauncher/data/'
                 'PrismLauncher/java/java-runtime-gamma')
    system_java = shutil.which('java')
    if jdk_value:
        java = Path(jdk_value).expanduser() / 'bin/java'
    elif system_java:
        java = Path(system_java).resolve()
    else:
        java = prism_jdk / 'bin/java'
    adb = sdk / 'platform-tools' / 'adb'
    data_root = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local' / 'share'))
    template_version = '.'.join(version.split('.')[:3]) + '.stable'
    templates = data_root / 'godot' / 'export_templates' / template_version
    local_templates = LOCAL_DATA / 'godot' / 'export_templates' / template_version
    if (local_templates / 'android_debug.apk').is_file():
        templates = local_templates
    return godot, version, sdk, java, adb, templates


def doctor():
    godot, version, sdk, java, adb, templates = configuration()
    signing_tool = apksigner(sdk)
    platform = android_platform(sdk)
    checks = [
        ('Godot', Path(godot), True),
        ('OpenJDK (17 recommended)', java, all(java.with_name(tool).is_file() for tool in ('java', 'javac', 'keytool'))),
        ('Android platform tools / ADB', adb, adb.is_file()),
        ('Android build tools', sdk / 'build-tools', signing_tool is not None and signing_tool.with_name('d8').is_file()),
        ('Android SDK platform (35 or newer)', platform or sdk / 'platforms/android-35', platform is not None),
        ('Matching Android debug export template', templates / 'android_debug.apk', (templates / 'android_debug.apk').is_file()),
    ]
    print(f'Havu Android build readiness · Godot {version}')
    for name, path, available in checks:
        print(f'{"OK     " if available else "MISSING"} {name}: {path}')
    ready = all(entry[2] for entry in checks)
    if not ready:
        print('\nSee docs/ANDROID.md for setup. No APK has been built.')
    return ready


def apksigner(sdk):
    tools = [path for path in (sdk / 'build-tools').glob('*/apksigner')
             if path.is_file() and path.with_name('zipalign').is_file()]
    preferred = sdk / 'build-tools/35.0.1/apksigner'
    return preferred if preferred in tools else next(iter(sorted(tools, reverse=True)), None)


def android_platform(sdk):
    versions = {}
    for jar in (sdk / 'platforms').glob('android-*/android.jar'):
        version = jar.parent.name.removeprefix('android-')
        if version.isdecimal() and int(version) >= 35:
            versions[int(version)] = jar
    return versions[max(versions)] if versions else None


def stage_android_template(templates, sdk, java, staging, env):
    """Add Havu's native Android input helpers to a copy of the engine's debug template."""
    classes = staging / 'classes'
    dex = staging / 'dex'
    classes.mkdir()
    dex.mkdir()
    platform = android_platform(sdk)
    sources = sorted((ROOT / 'tools/android').glob('*.java'))
    run([java.with_name('javac'), '--release', '8', '-cp', platform, '-d', classes, *sources], env=env)
    run([apksigner(sdk).with_name('d8'), '--min-api', '24', '--lib', platform, '--output', dex,
         *sorted(classes.rglob('*.class'))], env=env)

    data = staging / 'data'
    target_dir = data / 'godot/export_templates' / templates.name
    target_dir.mkdir(parents=True)
    (target_dir / 'version.txt').write_text(templates.name + '\n')
    template = 'android_debug.apk'
    with zipfile.ZipFile(templates / template) as stock, zipfile.ZipFile(target_dir / template, 'w') as output:
        dex_numbers = [int(match[1] or 1) for name in stock.namelist()
                       if (match := re.fullmatch(r'classes(\d*)\.dex', name))]
        entry = f'classes{max(dex_numbers) + 1}.dex'
        for info in stock.infolist():
            with stock.open(info) as original, output.open(info, 'w') as copy:
                shutil.copyfileobj(original, copy)
        output.write(dex / 'classes.dex', entry, compress_type=zipfile.ZIP_DEFLATED)
    return data, entry, (dex / 'classes.dex').read_bytes()


def write_build_config(version, sdk, java):
    """Create an isolated editor config that points at the actual SDK and JDK."""
    if not (java.is_file() and java.with_name('keytool').is_file()):
        raise RuntimeError('Set JAVA_HOME to a JDK with java and keytool.')
    ANDROID_STATE.mkdir(parents=True, exist_ok=True)
    if not DEBUG_KEY.is_file():
        with tempfile.TemporaryDirectory(dir=ANDROID_STATE) as temporary:
            key = Path(temporary) / 'debug.keystore'
            run([java.with_name('keytool'), '-genkeypair', '-keystore', key, '-storetype', 'JKS',
                 '-storepass', 'android', '-keypass', 'android', '-alias', 'androiddebugkey',
                 '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000', '-dname', 'CN=Havu Android Debug'])
            key.chmod(0o600)
            key.replace(DEBUG_KEY)
    config_file = LOCAL_CONFIG / 'godot' / ('editor_settings-' + '.'.join(version.split('.')[:2]) + '.tres')
    config_file.parent.mkdir(parents=True, exist_ok=True)
    entries = {
        'export/android/android_sdk_path': str(sdk),
        'export/android/java_sdk_path': str(java.parent.parent),
        'export/android/debug_keystore': str(DEBUG_KEY),
        'export/android/debug_keystore_user': 'androiddebugkey',
        'export/android/debug_keystore_pass': 'android',
    }
    config_file.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' +
                           ''.join(f'{key} = {json.dumps(value, ensure_ascii=False)}\n' for key, value in entries.items()))


def verify_download(path, expected):
    with path.open('rb') as archive:
        actual = hashlib.file_digest(archive, 'sha256').hexdigest()
    if actual != expected:
        raise RuntimeError(f'SHA-256 mismatch for {path.name}. Download a fresh official copy.')


def setup(downloads):
    _, version, sdk, java, adb, templates = configuration()
    signing_tool = apksigner(sdk)
    sdk_available = (adb.is_file() and signing_tool is not None and signing_tool.with_name('d8').is_file()
                     and android_platform(sdk) is not None)
    write_build_config(version, sdk if sdk_available else LOCAL_SDK, java)
    manager = LOCAL_SDK / 'cmdline-tools/latest/bin/sdkmanager'
    need_template = not (templates / 'android_debug.apk').is_file()
    if need_template and not version.startswith('4.7.2.stable.'):
        raise RuntimeError('Install Android export templates matching your editor using Manage Export Templates.')
    required = []
    if need_template:
        required.append((downloads / GODOT_TEMPLATE, GODOT_TEMPLATE_SHA))
    if not sdk_available and not manager.is_file():
        required.append((downloads / ANDROID_TOOLS, ANDROID_TOOLS_SHA))
    missing = [path for path, _ in required if not path.is_file()]
    if missing:
        raise RuntimeError('Download the missing archives listed in docs/ANDROID.md:\n' +
                           '\n'.join(str(path) for path in missing))
    for path, digest in required:
        print(f'Checking {path.name}…', flush=True)
        verify_download(path, digest)
    if need_template:
        target = LOCAL_DATA / 'godot/export_templates/4.7.2.stable'
        target.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=target) as temporary:
            path = Path(temporary) / 'android_debug.apk'
            shutil.copyfile(downloads / GODOT_TEMPLATE, path)
            (target / 'version.txt').write_text('4.7.2.stable\n')
            path.replace(target / path.name)
    if sdk_available:
        return doctor()
    if not manager.is_file():
        manager.parent.parent.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ANDROID_STATE) as temporary:
            with zipfile.ZipFile(downloads / ANDROID_TOOLS) as archive:
                archive.extractall(temporary)
            unpacked = Path(temporary) / 'cmdline-tools'
            for path in (unpacked / 'bin').iterdir(): path.chmod(0o755)
            unpacked.rename(manager.parent.parent)
    print('Installing Android SDK packages. Review any licenses shown by sdkmanager.', flush=True)
    env = dict(os.environ, JAVA_HOME=str(java.parent.parent), ANDROID_USER_HOME=str(ANDROID_STATE / 'user'))
    run([manager, f'--sdk_root={LOCAL_SDK}', *SDK_PACKAGES], env=env)
    return doctor()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['doctor', 'setup', 'build', 'devices', 'install'])
    parser.add_argument('--downloads', type=Path, default=Path.home() / 'Downloads')
    args = parser.parse_args()
    godot, version, sdk, java, adb, templates = configuration()
    if args.action == 'doctor':
        return 0 if doctor() else 1
    if args.action == 'setup':
        return 0 if setup(args.downloads) else 1
    if args.action == 'devices':
        if not adb.is_file():
            raise RuntimeError('ADB is missing. See docs/ANDROID.md.')
        run([adb, 'devices', '-l'])
        return 0
    if args.action == 'build':
        if not doctor():
            return 1
        write_build_config(version, sdk, java)
        APK.parent.mkdir(exist_ok=True)
        env = dict(os.environ, XDG_CONFIG_HOME=str(LOCAL_CONFIG),
                   XDG_CACHE_HOME=str(ANDROID_STATE / 'cache'), JAVA_HOME=str(java.parent.parent),
                   PATH=str(java.parent) + os.pathsep + os.environ.get('PATH', os.defpath))
        with tempfile.TemporaryDirectory(dir=APK.parent) as temporary:
            staged = Path(temporary) / APK.name
            data, native_entry, native_dex = stage_android_template(templates, sdk, java, staged.parent, env)
            env['XDG_DATA_HOME'] = str(data)
            run([godot, '--path', ROOT, '--headless', '--export-debug', 'Android', staged], env=env)
            if not staged.is_file() or staged.stat().st_size < 1_000_000:
                raise RuntimeError('Godot did not produce a usable APK.')
            with zipfile.ZipFile(staged) as apk:
                entries = apk.namelist()
                has_arm64 = any(name.startswith('lib/arm64-v8a/') and name.endswith('.so') for name in entries)
                if 'AndroidManifest.xml' not in entries or not has_arm64:
                    raise RuntimeError('The APK is missing its Android manifest or ARM64 engine.')
                if native_entry not in entries or apk.read(native_entry) != native_dex:
                    raise RuntimeError('The APK is missing the compiled Android input helpers.')
            run([apksigner(sdk), 'verify', staged], env=env)
            staged.replace(APK)
        print(f'Built {APK}')
        return 0
    if not adb.is_file():
        raise RuntimeError('ADB is missing. See docs/ANDROID.md.')
    if not APK.is_file():
        raise RuntimeError('Build the APK first: python3 tools/android.py build')
    output = subprocess.check_output([str(adb), 'devices'], text=True)
    devices = [line.split()[0] for line in output.splitlines()[1:] if len(line.split()) == 2 and line.split()[1] == 'device' and not line.startswith('emulator-')]
    if len(devices) != 1:
        raise RuntimeError('Connect exactly one authorized USB tablet; unlock it and accept its USB debugging prompt.')
    run([adb, '-s', devices[0], 'install', '-r', APK])
    command = [adb, '-s', devices[0], 'shell', 'am', 'start', '-W', '-a', 'android.intent.action.MAIN',
               '-c', 'android.intent.category.LAUNCHER', '-p', PACKAGE]
    launch = run(command, capture_output=True, text=True)
    if 'Error:' in launch.stdout + launch.stderr or 'Status: ok' not in launch.stdout:
        raise RuntimeError('Havu installed, but Android did not launch it. ' + (launch.stdout + launch.stderr).strip())
    print('Havu installed and launched. Existing app data was retained.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.CalledProcessError, OSError, zipfile.BadZipFile, KeyError) as error:
        print(f'Error: {error}', file=sys.stderr)
        sys.exit(1)
