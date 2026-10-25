# The values in the braces of markup (parsemarkup.zap), made by their type into what std/zapx
# builds: a child is a node as it is, a list of nodes their fragment, a str or a number its text;
# an attribute's value is a str, a number or a bool (written bare when true, left out when false).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# whether e is a value the markup's parser left to the checker (markupChildCall, markupAttrCall)
fn isMarkupValue(c Checker, e NodeId):
	callee = nodes[e].kids(kidIds)[0]
	nodes[callee].kind == nIdent and
		(nodes[callee].text == markupChildCall or nodes[callee].text == markupAttrCall)

fn isMarkupNode(c Checker, t TypeId):
	c.tKind(t) == tEnum and tys[t].name == "{prefixFor(markupModule)}Node"

# the markup value e checked: its value's type picks the call of std/zapx that takes it
fn checkMarkupValue(mut c Checker, e NodeId, expected TypeId?) TypeId:
	callee = nodes[e].kids(kidIds)[0]
	child = nodes[callee].text == markupChildCall
	value = nodes[e].kids(kidIds).last ?? fail("an element without its value")
	t = c.derefType(c.checkExpr(value, none))
	k = c.tKind(t)
	if k == tError: return c.typed(e, tyError)
	if child and c.isMarkupNode(t):
		nodes[e] = nodes[value].copy()   # a node is the child itself
		return c.checkExprRaw(e, expected)
	number = k == tInt or k == tFloat
	made = ""
	if child and k == tList and c.isMarkupNode(innerOf(tys, t)):
		made = "fragment"
	elif k == tStr or number:
		made = "text" if child else "attr"
	elif k == tBool and not child:
		made = "flag"
	if made == "":
		line = nodes[e].line
		col = nodes[e].col
		if child:
			c.errorAt(line, col, compileError("MarkupChildType", [c.showTy(t)]))
		else:
			c.errorAt(
				line,
				col,
				compileError(
					"MarkupAttributeType",
					[nodes[nodes[e].kids(kidIds)[1]].text.copy(), c.showTy(t)]
				)
			)
		return c.typed(e, tyError)
	if number:
		shown = nodes.interpolated(kidIds, value)
		nodes[e].setKid(kidIds, nodes[e].kidsLen - 1, shown)
	g = newNode(nodes, kidIds, nIdent, nodes[e].line, nodes[e].col, text = globalAlias)
	nodes[callee].kind = nField
	nodes[callee].text = "{prefixFor(markupModule)}{made}"
	nodes[callee].setKids(kidIds, [g])
	c.checkExpr(e, expected)
