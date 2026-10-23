# The builds the project knows, by main's build id: the game and version a dump is.

type Build:
	buildId str
	what str

knownBuilds = [
	Build(
		buildId = "2094f152836683a3632c6153fd84ab8000000000",
		what = "Zelda: Breath of the Wild 1.0.0"
	)
]

# what the table knows a main of this build id as, or "not known"
pub fn knownBuild(buildId str) str:
	knownBuilds.filter(.buildId == buildId).first?.what ?? "not known"
