# The book menu (book.swf, BookMenu): the text set by GameDelegate's SetBookText (the book's DESC
# from the .DLSTRINGS, a note's flag), the movie paginating it itself, turned by
# BookMenu.BookMenuInstance.TurnPage and shown page by page by ShowPageAtOffset (0x140907130).
# BookMenu::ProcessMessage (0x1409063d0) turns by 2 a book's spread and 1 a note's page: NextPage
# and RightEquip forward, PrevPage and LeftEquip back (the delta's sign flipped), ITMNotePageTurn
# sounding for a note; Cancel closes, Accept takes a book that lies in the world. The game draws
# the pages onto its animated book model (render targets on Book01.nif); here they are drawn flat,
# a book's two pages side by side, a note's one.

import engine
import engine.swf
import engine.swf.avm1
import game.sim
import skyrim

pub type BookMenu:
	p avm1.Player
	book i64   # the book's base form
	at i64   # the reference it lies as in the world, 0 when read from an inventory
	note bool
	open bool = true

# the book `book` opened on its first pages, `at` its reference in the world (0 for none)
pub fn openBook(
	install skyrim.Install,
	t GameTexts,
	w sim.GameWorld,
	book i64,
	at i64,
	width i64,
	height i64
) BookMenu ? str:
	data = (w.items.get(book) ?? return "{book:08X} is no item").kind.Book ??
		return "{book:08X} is no book"
	text = t.descriptions.texts.get(data.textId) ?? ""
	p = try install.openPlayer("interface/book.swf", width, height)
	# the movie's onLoad registers the GameDelegate callbacks
	p.advance()
	p.delegate("SetBookText", [.Str(text.copy()), .Bool(data.note)])
	BookMenu(p, book, at, note = data.note)

# The pages turned forward or back, as the game's keys turn them; whether they turned (the movie
# refuses past the first and the last).
pub fn turnPage(mut b BookMenu, forward bool) bool:
	step = 1.0 if b.note else 2.0
	turned = b.p.invoke("BookMenu.BookMenuInstance.TurnPage", [.Num(step if forward else -step)])
	turned.isTrue()

# A page turned (or not) heard: a note's turn sounds, a book's is the animated model's.
pub fn heardPage(mut w sim.GameWorld, turned bool, note bool):
	if turned and note: w.playUi(notePageTurnSound)

# the open pages drawn over the window's middle
pub fn drawBook(
	mut b BookMenu,
	mut cache swf.DrawCache,
	mut r engine.Renderer,
	width i64,
	height i64
):
	pages = 1 if b.note else 2
	h = f32(height) * 0.8
	w = h * 300.0 / 475.0
	left = (f32(width) - w * f32(pages)) * 0.5
	for k in 0..pages:
		b.p.invoke("BookMenu.BookMenuInstance.ShowPageAtOffset", [.Num(f64(k))])
		b.p.drawInto(cache, r, left + w * f32(k), f32(height) * 0.1, w, h)
