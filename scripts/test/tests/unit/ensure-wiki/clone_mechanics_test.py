#!/usr/bin/env python3
"""try_clone staging+rename mechanics: partial-clone (#1) and concurrency (#4).

Exercises ensure_wiki.try_clone directly with real git, so it bypasses the
GitHub-only URL gate. Usage: clone_mechanics_test.py <path-to-ensure-wiki.py>

Demonstrates the contrast the fix is about: a clone interrupted mid-write must
strand nothing at the canonical path (the next session retries), and N
concurrent clones must converge on exactly one checkout. A built-in contrast
block shows the OLD direct-to-canonical approach DOES strand a partial dir, so
this test could fail if the staging logic regressed.
"""
import importlib.util
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

hook_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("ensure_wiki", hook_path)
ew = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ew)

results = []
def check(label, cond):
    results.append((label, bool(cond)))


def make_upstream(base: Path) -> str:
    up = base / "upstream"
    up.mkdir()
    g = ["-c", "user.email=t@t", "-c", "user.name=t"]
    subprocess.run(["git", "init", "-q", str(up)], check=True)
    (up / "README.md").write_text("wiki seed\n")
    subprocess.run(["git", "-C", str(up), "add", "."], check=True)
    subprocess.run(["git", "-C", str(up), *g, "commit", "-q", "-m", "seed"], check=True)
    return str(up)


def staging_leftovers(repo_root: Path) -> list:
    p = repo_root / "wiki"
    if not p.is_dir():
        return []
    return [d for d in p.iterdir() if d.name.startswith(".ensure-wiki-")]


def fresh_repo(base: Path, name: str):
    repo_root = base / name
    (repo_root / "wiki").mkdir(parents=True)
    return repo_root, f"wiki/{name}.wiki"


with tempfile.TemporaryDirectory() as td:
    base = Path(td)
    upstream = make_upstream(base)

    # A: happy path publishes a complete checkout, no staging residue.
    repo_root, wiki_rel = fresh_repo(base, "alpha")
    ok = ew.try_clone(["git", "clone", upstream, wiki_rel], repo_root, wiki_rel)
    canon = repo_root / wiki_rel
    check("happy: returns True", ok)
    check("happy: canonical .git present", (canon / ".git").exists())
    check("happy: no staging leftovers", staging_leftovers(repo_root) == [])

    # B: an interrupted clone strands nothing at the canonical path (#1).
    repo_root, wiki_rel = fresh_repo(base, "beta")
    faker = base / "faker.sh"
    faker.write_text('#!/usr/bin/env bash\nd="${@: -1}"\nmkdir -p "$d"\necho partial > "$d/PARTIAL"\nexit 137\n')
    faker.chmod(0o755)
    ok = ew.try_clone(["bash", str(faker), wiki_rel], repo_root, wiki_rel)
    canon = repo_root / wiki_rel
    check("interrupted: returns False", ok is False)
    check("interrupted: canonical path absent (FIX #1)", not canon.exists())
    check("interrupted: no staging leftovers", staging_leftovers(repo_root) == [])

    # Contrast: the old direct-to-canonical clone WOULD strand a partial dir,
    # proving this test discriminates (it would fail if staging regressed).
    old_repo, old_rel = fresh_repo(base, "beta_old")
    old_canon = old_repo / old_rel
    subprocess.run(["bash", str(faker), str(old_canon)])
    check("contrast: direct-to-canonical strands a half-written dir", old_canon.is_dir())

    # C: N concurrent clones converge on exactly one checkout (#4).
    repo_root, wiki_rel = fresh_repo(base, "gamma")
    N = 6
    outcomes = [None] * N
    errors = [None] * N
    barrier = threading.Barrier(N)

    def worker(i):
        try:
            barrier.wait()
            outcomes[i] = ew.try_clone(["git", "clone", upstream, wiki_rel], repo_root, wiki_rel)
        except Exception as e:  # noqa: BLE001
            errors[i] = repr(e)

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(N)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    canon = repo_root / wiki_rel
    wiki_dirs = [d for d in (repo_root / "wiki").iterdir() if d.name.endswith(".wiki")]
    check("race: no worker raised", all(e is None for e in errors))
    check("race: every worker reports success", all(o is True for o in outcomes))
    check("race: exactly one .wiki dir (the canonical one)", wiki_dirs == [canon])
    check("race: canonical .git present", (canon / ".git").exists())
    check("race: no staging leftovers", staging_leftovers(repo_root) == [])

failed = [l for l, c in results if not c]
for l, c in results:
    print(f"  [{'PASS' if c else 'FAIL'}] {l}", file=sys.stderr)
if failed:
    print("FAILED: " + "; ".join(failed), file=sys.stderr)
    sys.exit(1)
sys.exit(0)
