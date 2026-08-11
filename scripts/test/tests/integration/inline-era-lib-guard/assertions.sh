#!/usr/bin/env bash
# Assertions: on a host missing the shared lib, the sync scripts must fail
# with a DIAGNOSTIC (vintage named, exact adopt recovery command printed),
# not a raw bash `source` error (#92).

STAGE="$SANDBOX/inline-era-lib-guard"
H="$STAGE/host"

for _script in update-from-template.sh check-template-version.sh; do
    _log="$STAGE/${_script%.sh}.log"
    ( cd "$H" && bash "scripts/$_script" ) > "$_log" 2>&1
    _rc=$?
    assert "$_script exits non-zero without the lib" "[ $_rc -ne 0 ]"
    assert "$_script names the missing lib and the vintage" \
        "grep -qF 'predates the shared library' '$_log'"
    assert "$_script prints the adopt recovery command" \
        "grep -qF -- '--apply --force' '$_log'"
    assert "$_script points at issue #92" \
        "grep -qF 'issues/92' '$_log'"
done
