# The scripts bench: a throwaway script's time end to end, as an agent meets it. Each problem of
# problems/ is a Zap script run by `zap run` after an edit of it (its compile included, the
# build's caches warm) and, apart, unchanged, against the same script in Python; std/compare's
# script race keeps the ratio of Zap edited over Python in bench.baseline (spec 13.1).
#
#   zap test --only bench tests/scripts [script name]
import compare
import problems

problems.prepare()
compare.suite(problems.problems(), _: "", args)
