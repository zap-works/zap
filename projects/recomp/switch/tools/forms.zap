# Writes cpu/forms.zap, the interpreter's functions for the operations forms/forms.zap writes, as
# zap fmt lays them out (cpu/tests/forms.zap checks it is current). Run from the repository root:
#
#   zap run projects/recomp/switch/tools/forms.zap

import recomp.switch.forms

path = "projects/recomp/switch/cpu/forms.zap"
forms.writeInterpreter(path, zapPath()) ?? fail
print("{path} written")
