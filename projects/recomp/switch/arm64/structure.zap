# A64's loads and stores of vector structures (Arm ARM C4.1.4): ld1-ld4 and st1-st4 of multiple
# structures or of one lane, and ld1r-ld4r, with their post-index forms.

# The structure access w (its rt and rn read), Op.Unknown when it is none the decoder knows.
fn vectorStructure(w i64, rt i64, rn i64):
	Instr()
