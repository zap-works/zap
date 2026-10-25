# a binding whose value a call that counts gives
mut calls = 0

fn made() i64:
	calls += 1
	calls * 10

pub value = made()
pub label = "made {made()}"
