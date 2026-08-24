"""Per-strip-type "is this lot fully tested yet" rules for the lot checking
progress tracker (build_progress.py).

Hand-maintained literals, matching this codebase's existing idiom for
COL/SUBSTANCES/LEVEL_MG in build_fts.py/build_xts.py -- not inferred from
anything, not a generic/pluggable config system. Extend by adding a new
STRIP_TYPES entry when a new strip type's build script (build_bts.py,
build_nts.py, ...) exists; see the wiki's Target-Extension-Recipe.md for
the matching build-script-side extension steps.

A lot is "fully tested" when, for every entry in `targets`, the target's
run count is >= min_run; the true_negative run count is >= min_run; and
every substance in `interferences` is either never positive at `hi_mg`,
or -- if positive at `hi_mg` -- has also been run at one of `follow_up_mgs`
(regardless of that follow-up's own result; the point is characterizing
the interference, not requiring it to disappear). Plus >=1 packaging photo
and >=1 strip photo (checked by build_progress.py directly against
n_photos_packaging/n_photos_strip, not part of this config since it's the
same rule for every strip type).

Deliberately just run-count coverage, not pass/fail rate -- Marya's rule
is "have we tested enough," not "did it pass." Each dashboard's own page
(fts.html/xts.html) already shows detection/false-positive rates in full
detail; this file only names which field holds each count.
"""

STRIP_TYPES = {
    'FTS': {
        'label': 'Fentanyl (FTS)',
        'dashboard': 'fts',
        'dashboard_href': 'fts.html',
        # One entry per target analyte. FTS has just one; multi-target
        # strips (future BTS/NTS panels) list one entry per model molecule,
        # each independently needing min_run -- see XTS below for the
        # multi-panel shape this is modeled on.
        'targets': [
            {'code': 'fen', 'label': 'Fentanyl', 'run_field': 'fen_run', 'min_run': 25},
        ],
        'true_negative': {'run_field': 'wat_run', 'min_run': 5},
        'interferences': ['DIPHEN', 'PROC', 'LIDO', 'LEVAM', 'MDONE', 'METH', 'MDMA'],
        'hi_mg': 2.0, 'follow_up_mgs': [0.7, 0.2],
    },
    'XTS': {
        'label': 'Xylazine (XTS)',
        'dashboard': 'xts',
        'dashboard_href': 'xts.html',
        'targets': [
            {'code': 'tp_2500_di', 'label': 'Xylazine 2500 ng/mL, DI water', 'run_field': 'tp_2500_di_run', 'min_run': 25},
            {'code': 'tp_2500_tap', 'label': 'Xylazine 2500 ng/mL, tap water', 'run_field': 'tp_2500_tap_run', 'min_run': 25},
            {'code': 'tp_1000_di', 'label': 'Xylazine 1000 ng/mL, DI water', 'run_field': 'tp_1000_di_run', 'min_run': 25},
        ],
        # Just the run count matters here (tn_run), same as FTS's wat_run --
        # note for anyone tempted to also surface a pass/fail rate later:
        # XTS's tn_pos counts POSITIVE-on-water reads, i.e. failures, the
        # opposite sense of FTS's wat_true_neg, which counts passes. Fine
        # to ignore for coverage-only completion, but a real trap if this
        # file ever grows a rate display without accounting for it.
        'true_negative': {'run_field': 'tn_run', 'min_run': 5},
        'interferences': [
            'DIPHEN', 'KETA', 'LIDO', 'PREMETH', 'CETIRI', 'METH', 'MDMA',
            'ROMI', 'TIZA', 'CLONI', 'APRACLONI',
        ],
        'hi_mg': 2.0, 'follow_up_mgs': [0.7, 0.2],
    },
    # BTS / MTS / NTS: no build_bts.py/build_mts.py/build_nts.py exists yet
    # (see wiki Target-Extension-Recipe.md) -- add an entry here once one
    # does. Until then, build_progress.py shows lots logged with one of
    # these strip types as "in lab, testing status not yet supported"
    # rather than erroring.
}
