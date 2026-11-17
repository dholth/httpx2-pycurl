#!/usr/bin/env bash
# Check out pydantic/httpx2 next to this repo, apply tests/httpx2-tests.patch,
# and run the httpx2 test suite against httpx2-pycurl's transport.
#
# Re-running is safe: if httpx2 is already checked out and patched, only the
# tests are run.
#
# Usage: ./run-httpx2-tests.sh [--own] [pytest arguments...]
#
#   --own    also run httpx2-pycurl's own tests (needs nginx; see the CI workflow)
#
# Environment:
#   HTTPX2_DIR   where to check out httpx2 (default: ../httpx2)
#   HTTPX2_REPO  git URL or path to clone (default: https://github.com/pydantic/httpx2)
#   PYTHON       interpreter or pytest script to use (default: httpx2/.venv/bin/python,
#                then python, then python3)
#   PYTEST       pytest command to run instead of "<python> -m pytest"
#
# The interpreter must be able to import the httpx2 test dependencies; see the
# dependency check below. Missing pycurl and httpx2-pycurl are installed
# automatically.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
patch_file="$here/tests/httpx2-tests.patch"
httpx2_dir="${HTTPX2_DIR:-$(dirname "$here")/httpx2}"
httpx2_repo="${HTTPX2_REPO:-https://github.com/pydantic/httpx2}"

# Mirrors the exclusions used by .github/workflows/python-package-conda.yml.
test_selection="not anyio and not test_main and not autodetect and not cp_1252 and not cp1252 and not explicit_encoding"

run_own=0
while [ $# -gt 0 ]; do
    case "$1" in
        --own)
            run_own=1
            shift
            ;;
        -h|--help)
            awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

if [ ! -d "$httpx2_dir" ] || [ -z "$(ls -A "$httpx2_dir")" ]; then
    echo "Cloning $httpx2_repo into $httpx2_dir"
    git clone "$httpx2_repo" "$httpx2_dir"
elif [ ! -d "$httpx2_dir/.git" ]; then
    echo "error: $httpx2_dir exists but is not a git checkout" >&2
    echo "Remove it or set HTTPX2_DIR to a directory that can be cloned into." >&2
    exit 1
fi

interpreter_works() {
    [ -n "${1:-}" ] && "$1" -c 'pass' >/dev/null 2>&1
}

# PYTHON may name an interpreter or a pytest script such as
# .venv/bin/pytest. Fall back to a neighboring interpreter or its shebang.
python="${PYTHON:-}"
if [ -n "$python" ] && ! interpreter_works "$python"; then
    pytest_script="$python"
    python="$(dirname "$pytest_script")/python"
    if ! interpreter_works "$python"; then
        shebang="$(head -n1 "$pytest_script" 2>/dev/null || true)"
        shebang="${shebang#\#!}"
        python="${shebang%% *}"
    fi
    if ! interpreter_works "$python"; then
        echo "error: PYTHON=$PYTHON is neither a Python interpreter nor a pytest script that points at one" >&2
        exit 1
    fi
fi

if [ -z "$python" ]; then
    for candidate in "$httpx2_dir/.venv/bin/python" python python3; do
        if interpreter_works "$candidate"; then
            python="$candidate"
            break
        fi
    done
fi

if [ -z "$python" ]; then
    echo "error: no Python interpreter found; set PYTHON to one" >&2
    exit 1
fi

has_module() {
    "$python" -c "import $1" >/dev/null 2>&1
}

# uv-managed virtualenvs do not ship pip, so prefer uv when it is available.
pip_install() {
    if command -v uv >/dev/null 2>&1; then
        uv pip install --python "$python" "$@"
    else
        "$python" -m pip install "$@"
    fi
}

missing_modules() {
    "$python" -c '
import importlib.util
mods = [
    "pytest", "pycurl", "certifi", "httpx2", "anyio", "trio", "uvicorn", "trustme",
    "pytest_trio", "starlette", "chardet", "brotli", "hpack", "hyperframe", "h2",
    "cryptography",
]
print(", ".join(m for m in mods if importlib.util.find_spec(m) is None))
' 2>/dev/null
}

missing="$(missing_modules)" || {
    echo "error: cannot inspect $python; set PYTHON to a working interpreter" >&2
    exit 1
}

# pycurl is not part of httpx2's dev dependencies, so install it when needed.
case ",$missing," in
    *",pycurl,"*)
        echo "Installing pycurl into $python"
        pip_install pycurl
        missing="$(missing_modules)" || {
            echo "error: cannot inspect $python; set PYTHON to a working interpreter" >&2
            exit 1
        }
        ;;
esac

if [ -n "$missing" ]; then
    echo "error: $python is missing modules needed by the httpx2 tests: $missing" >&2
    echo "Refresh that environment's httpx2 dev dependencies, e.g.:" >&2
    echo "  (cd $httpx2_dir && uv sync --group dev)" >&2
    echo "then re-run this script, or set PYTHON to an environment that has them." >&2
    exit 1
fi

if ! has_module httpx2_pycurl; then
    echo "Installing httpx2-pycurl into $python"
    pip_install --no-deps -e "$here"
fi

if [ -n "${PYTEST:-}" ]; then
    case "$PYTEST" in
        /*) pytest_cmd=("$PYTEST") ;;
        */*) pytest_cmd=("$PWD/$PYTEST") ;;
        *) pytest_cmd=("$(command -v "$PYTEST" || echo "$PYTEST")") ;;
    esac
else
    pytest_cmd=("$python" -m pytest)
fi

cd "$httpx2_dir"
if git apply --check "$patch_file" 2>/dev/null; then
    echo "Applying $(basename "$patch_file") to $httpx2_dir"
    git apply "$patch_file"
elif git apply --reverse --check "$patch_file" 2>/dev/null; then
    echo "$httpx2_dir is already patched"
else
    echo "error: cannot apply $patch_file to $httpx2_dir" >&2
    echo "Regenerate the patch against the current httpx2 checkout." >&2
    exit 1
fi

if [ "$run_own" -eq 1 ]; then
    echo "Running httpx2-pycurl tests"
    (cd "$here" && "${pytest_cmd[@]}")
fi

echo "Running httpx2 tests with the httpx2-pycurl transport"
exec "${pytest_cmd[@]}" tests/httpx2 --ignore=tests/httpx2/websockets -k "$test_selection" -v "$@"
