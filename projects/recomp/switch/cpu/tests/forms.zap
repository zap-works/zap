# cpu/forms.zap is what tools/forms.zap writes from the translation's forms today.

import fs
import recomp.switch.forms

test "the interpreter's forms are the translation's":
	expect (fs.readFile("projects/recomp/switch/cpu/forms.zap") ?? "") == forms.interpreterForms()
