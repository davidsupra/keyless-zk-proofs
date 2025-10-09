import subprocess
import sys
from utils import eprint
import utils
import platform
import shutil
import os
from collections import OrderedDict

def install_nvm():
    """Install NVM (Node Version Manager)."""
    utils.download_and_run_shell_script("https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh")

def install_node():
    """Install nvm, and then use it to install nodejs."""
    eprint("Installing node")
    install_nvm()
    nvm_dir = os.environ.get("NVM_DIR", os.path.expanduser("~/.nvm"))
    utils.run_shell_command(
        "bash -lc 'export NVM_DIR=\"{nvm_dir}\"; "
        "[ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"; "
        "nvm install node'".format(nvm_dir=nvm_dir)
    )
    eprint("Installation of node succeeded")

def install_circom():
    if shutil.which("circom"):
        try:
            existing_version = subprocess.check_output(["circom", "--version"], text=True).strip()
        except Exception:
            existing_version = None
        if existing_version:
            eprint(f"circom already installed ({existing_version}); skipping")
            return

    eprint("Installing circom")
    # de2212a7aa6a070c636cc73382a3deba8c658ad5 fixes a bug related to tag propagation
    # TODO: replace to v2.2.3 once released (because v2.2.2 has a bug related to tags, which we want to use)
    utils.cargo_install_from_git("https://github.com/iden3/circom", "de2212a7aa6a070c636cc73382a3deba8c658ad5")
    eprint("Installation of circom succeeded")

def install_circomlib():
    eprint("Installing circomlib")
    install_npm_package("circomlib@2.0.5")
    eprint("Installation of circomlib succeeded")

def install_snarkjs():
    eprint("Installing snarkjs")
    install_npm_package("snarkjs@0.7.5")
    eprint("Installation of snarkjs succeeded")

def install_rust():
    eprint("Checking for rustup...")
    if shutil.which("rustup"):
        eprint("Rustup installed.")
    else:
        eprint("Rustup not installed, installing...")
        utils.download_and_run_shell_script_with_opts(
                "https://sh.rustup.rs",
                "-y --default-toolchain stable"
                )
        eprint("Installation of rustup succeeded. Setting path environment variable...")

        add_cargo_to_path()

        eprint("Done.")


def add_cargo_to_path():
    if "CARGO_HOME" in os.environ:
        utils.add_envvar_to_profile("PATH", "$PATH:" + os.environ["CARGO_HOME"] + "/bin")
        os.environ['PATH'] += ":" + os.environ["CARGO_HOME"] + "/bin"
    else:
        utils.add_envvar_to_profile("PATH", "$PATH:" + os.path.expanduser("~/.cargo/bin"))
        os.environ['PATH'] += ":" + os.path.expanduser("~/.cargo/bin")

def install_npm_package(package):
    nvm_dir = os.environ.get("NVM_DIR", os.path.expanduser("~/.nvm"))
    utils.run_shell_command(
        "bash -lc 'export NVM_DIR=\"{nvm_dir}\"; "
        "[ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"; "
        "npm install -g {package}'".format(
            nvm_dir=nvm_dir,
            package=package.replace("'", "'\"'\"'")
        )
    )

def platform_package_manager():
    if platform.system() == 'Linux':
        if shutil.which("apt-get"):
            return "apt-get"
        elif shutil.which("pacman"):
            return "pacman"
        else:
            eprint("Couldn't find a package manager. On linux, this script currently only supports apt-get (debian and ubuntu) and pacman (arch linux).")
            exit(2)
    elif platform.system() == 'Darwin':
        if shutil.which("brew"):
            return "brew"
        else:
            eprint("Couldn't find a package manager. On macos, this script requires brew. Please install it.")
            exit(2)
    else:
        eprint("System type " + platform.system() + " is not supported. This script currently only supports macos and linux.")
        exit(2)

    return "brew"


_apt_pending_packages = OrderedDict()
_apt_installed_packages = set()


def _queue_apt_package(dep_name, package):
    if package in _apt_installed_packages:
        return False
    if package not in _apt_pending_packages:
        _apt_pending_packages[package] = []
    if dep_name is not None and dep_name not in _apt_pending_packages[package]:
        _apt_pending_packages[package].append(dep_name)
    return True


def flush_apt_queue():
    if not _apt_pending_packages:
        return
    packages = list(_apt_pending_packages.keys())
    try:
        utils.run_shell_command("apt-get update", as_root=True)
        utils.run_shell_command("apt-get install -y " + " ".join(packages), as_root=True)
    except Exception as e:
        eprint("Installing " + ", ".join(packages) + " failed. Exception: ")
        eprint(e)
        eprint("Exiting.")
        exit(2)
    for package, deps in _apt_pending_packages.items():
        _apt_installed_packages.add(package)
        for dep in deps:
            eprint("Done installing " + dep)
    _apt_pending_packages.clear()


def run_platform_package_manager_command(package, package_manager=None, dep_name=None):
    if package_manager is None:
        package_manager = platform_package_manager()
    try:
        if package_manager == "brew":
            utils.run_shell_command("brew install " + package)
            return "installed"
        elif package_manager == "pacman":
            utils.run_shell_command("pacman -S --needed --noconfirm " + package, as_root=True)
            return "installed"
        elif package_manager == "apt-get":
            queued = _queue_apt_package(dep_name or package, package)
            return "deferred" if queued else "already_installed"
    except Exception as e:
        eprint("Installing " + package + " failed. Exception: ")
        eprint(e)
        eprint("Exiting.")
        exit(2)
    return "installed"


def install_using_package_manager(name, package):
    package_manager = platform_package_manager()

    if isinstance(package, str):
        package_name = package
    elif isinstance(package, dict):
        if package_manager not in package:
            eprint("Don't know a way to install package " + name + " on the current distribution.")
            exit(2)
        package_name = package[package_manager]
        if package_name is None:
            eprint("The current system doesn't need to install " + name + ".")
            eprint("Done installing " + name)
            return
    else:
        eprint("Dependency descriptor for " + name + " is invalid.")
        exit(2)

    if package_manager == "apt-get" and package_name in _apt_installed_packages:
        eprint(name + " already satisfied via apt-get.")
        eprint("Done installing " + name)
        return

    eprint("Installing " + name)
    result = run_platform_package_manager_command(package_name, package_manager, dep_name=name)

    if package_manager == "apt-get":
        if result == "already_installed":
            eprint("Done installing " + name)
    else:
        eprint("Done installing " + name)


# This dict defines the installation behavior for each dependency.
# - If dict[dep] is a function, calling that function should install the dep.
# - If dict[dep] is a string, this string is a package name which should be installed using
#   the system package manager.
# - If dict[dep] is a dict, this means that different platorm package managers have different
#   names for this dep, and the dict contains these platform-specific names.
deps_by_platform = {
        "node": install_node,
        "circom": install_circom,
        "circomlib": install_circomlib,
        "snarkjs": install_snarkjs,
        "meson": "meson",
        "rust": install_rust,
        "pkg-config": "pkg-config",
        "cmake": "cmake",
        "make": "make",
        "clang": {
            "brew": None,
            "pacman": "clang",
            "apt-get": "clang"
            },
        "nasm": "nasm",
        "lld": {
            "brew": None,
            "pacman": "lld",
            "apt-get": "lld"
            },
        "libyaml": {
            "brew": "libyaml",
            "pacman": "libyaml",
            "apt-get": "libyaml-dev"
            },
        "gmp": {
            "brew": "gmp",
            "pacman": "gmp",
            "apt-get": "libgmp-dev"
            },
        "openssl": {
            "brew": None,
            "pacman": "openssl",
            "apt-get": "libssl-dev"
            },
        "nlohmann-json": {
            "brew": "nlohmann-json",
            "pacman": "nlohmann-json",
            "apt-get": "nlohmann-json3-dev"
            }
        }


def install_dep(dep):
    if dep not in deps_by_platform:
        eprint("Dependency " + dep + " not recognized.")
        exit(2)
    handler = deps_by_platform[dep]

    # deps_by_platform[dep] is either ...
    if callable(handler):
        # ... a function, which means calling it should install the dep ...
        flush_apt_queue()
        handler()
    else:
        # ... or is a string or dict specifying a name that the system package
        # manager should use to install the package. In that case, use the system
        # package manager.
        install_using_package_manager(dep, handler)


def install_deps(deps):
    for dep in deps:
        install_dep(dep)
    flush_apt_queue()
