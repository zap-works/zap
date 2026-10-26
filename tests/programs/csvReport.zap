# Parses CSV lines from stdin into records, aggregates by category, prints a formatted report.
type Sale:
	region str
	product str
	units i64
	price f64
fn parse(line str) Sale ? str:
	cols = line.split(",")
	if cols.len != 4: return "expected 4 columns, got {cols.len}: {line}"
	units = i64.parse(cols[2].trimmed())
	price = f64.parse(cols[3].trimmed())
	match units:
		u: match price:
			p: return Sale(
				region = cols[0].trimmed().copy(),
				product = cols[1].trimmed().copy(),
				units = u,
				price = p
			)
			none: return "bad price: {cols[3]}"
		none: return "bad units: {cols[2]}"
mut sales = []
mut errors = []
mut first = true
mut line = stdin.line()
while line != none:
	text = line ?? ""
	if first:
		first = false
	elif not text.trimmed().isEmpty:
		match parse(text):
			s: sales.push(s)
			error: errors.push(error)
	line = stdin.line()
mut byRegion {str: f64} = {}
mut unitsByProduct {str: i64} = {}
for s in sales:
	revenue = (byRegion.get(s.region) ?? 0.0) + s.units * s.price
	byRegion[s.region.copy()] = revenue
	unitsByProduct.add(s.product, s.units)
print("Revenue by region")
for r in byRegion.keys().sorted():
	print("  {r:<8} {(byRegion.get(r) ?? 0.0):>10.2}")
print("Units by product")
for p in unitsByProduct.keys().sorted():
	print("  {p:<8} {(unitsByProduct.get(p) ?? 0):>6}")
total = sales.map(.units * .price).sum()
print("Total: {total:.2} from {sales.len} rows, {errors.len} rejected")
for e in errors:
	eprint("skipped: {e}")
ranked = sales.sortedBy(-(.units * .price))
match ranked.first:
	s: print("Top sale: {s.product} in {s.region}")
	none: print("No sales")

test "CSV lines from stdin add up by category into the report":
	stdin.feed("""
		region,product,units,price
		north,widget,10,2.50
		south,gadget,3,10.00
		north,gadget,1,9.99
		bad line
		east,widget,x,1.0
		south,widget,7,2.50

		""")
	main()
	prints """
	    Revenue by region
	      north         34.99
	      south         47.50
	    Units by product
	      gadget        4
	      widget       17
	    Total: 82.49 from 4 rows, 2 rejected
	    Top sale: gadget in south
	    """
