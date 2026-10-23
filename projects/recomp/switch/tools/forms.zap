# Writes cpu/forms.zap, the interpreter's functions for the operations translate/forms.zap writes
# (cpu/tests/forms.zap checks it is current). Run from the repository root:
#
#   zap run projects/recomp/switch/tools/forms.zap

import fs
import recomp.switch.forms

path = "projects/recomp/switch/cpu/forms.zap"
if fs.writeChanged(path, forms.interpreterForms().bytes()) ?? fail("cannot write {path}: {error}"):
	print("{path} written")
