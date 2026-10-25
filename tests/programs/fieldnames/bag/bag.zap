# a type whose method reads its field bare
pub type Bag:
	items i64[]

	pub fn count() i64:
		items.len
