import shutil
import utils
from utils import eprint
import os
import stat
import pathlib
import subprocess
import typer

app = typer.Typer(no_args_is_help=True)


@app.command()
def compute_sample_proof(skip_log_check: bool = typer.Option(False, help="Skip checking MyLogFile.log for the GPU marker")):
    """Generate a toy proof and confirm the GPU backend is reachable."""

    script_path = utils.repo_root() / "scripts" / "run_gpu_sanity.sh"
    if not script_path.exists():
        eprint(f"gpu sanity script missing at {script_path}")
        raise typer.Exit(code=2)

    command = [str(script_path)]
    if skip_log_check:
        command.append("--skip-log-check")

    result = subprocess.run(command)
    if result.returncode != 0:
        raise typer.Exit(code=result.returncode)


@app.command()
def install_circom_precommit_hook():
    """Install a pre-commit hook that requires the main circuit to compile before committing."""

    eprint("Installing precommit hook...")

    hook_src_path = utils.repo_root() + "/git-hooks/compile-circom-if-needed-pre-commit"
    hook_dest_path = utils.repo_root() + "/.git/hooks/pre-commit"
    eprint(hook_src_path)
    eprint(hook_dest_path)

    

    pathlib.Path(hook_dest_path).unlink(True)
    shutil.copyfile(hook_src_path, hook_dest_path)
    os.chmod(hook_dest_path, stat.S_IXUSR | stat.S_IRUSR | stat.S_IWUSR)
    
    eprint("Done.")

