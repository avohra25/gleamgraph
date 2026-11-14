//// A persistent min pairing heap keyed by integer priorities.
////
//// `insert` and `merge` are O(1); `pop` is O(log n) amortised. Ties are
//// broken arbitrarily but deterministically.

import gleam/list

pub opaque type Heap(a) {
  Empty
  Node(key: Int, value: a, children: List(Heap(a)))
}

pub fn new() -> Heap(a) {
  Empty
}

pub fn is_empty(heap: Heap(a)) -> Bool {
  heap == Empty
}

pub fn insert(heap: Heap(a), key: Int, value: a) -> Heap(a) {
  meld(heap, Node(key, value, []))
}

pub fn from_list(items: List(#(Int, a))) -> Heap(a) {
  list.fold(items, Empty, fn(h, item) { insert(h, item.0, item.1) })
}

/// Combine two heaps.
pub fn merge(a: Heap(a), b: Heap(a)) -> Heap(a) {
  meld(a, b)
}

/// The minimum `#(key, value)` without removing it.
pub fn peek(heap: Heap(a)) -> Result(#(Int, a), Nil) {
  case heap {
    Empty -> Error(Nil)
    Node(key, value, _) -> Ok(#(key, value))
  }
}

/// Remove the minimum, returning `#(key, value, rest)`.
pub fn pop(heap: Heap(a)) -> Result(#(Int, a, Heap(a)), Nil) {
  case heap {
    Empty -> Error(Nil)
    Node(key, value, children) -> Ok(#(key, value, merge_pairs(children)))
  }
}

pub fn size(heap: Heap(a)) -> Int {
  case heap {
    Empty -> 0
    Node(_, _, children) ->
      list.fold(children, 1, fn(acc, child) { acc + size(child) })
  }
}

/// Drain the heap in ascending key order.
pub fn to_sorted_list(heap: Heap(a)) -> List(#(Int, a)) {
  drain(heap, [])
}

fn drain(heap: Heap(a), acc: List(#(Int, a))) -> List(#(Int, a)) {
  case pop(heap) {
    Error(Nil) -> list.reverse(acc)
    Ok(#(key, value, rest)) -> drain(rest, [#(key, value), ..acc])
  }
}

fn meld(a: Heap(a), b: Heap(a)) -> Heap(a) {
  case a, b {
    Empty, h -> h
    h, Empty -> h
    Node(ka, va, ca), Node(kb, vb, cb) ->
      case ka <= kb {
        True -> Node(ka, va, [b, ..ca])
        False -> Node(kb, vb, [a, ..cb])
      }
  }
}

// Two-pass pairing: meld neighbours left to right, then fold right to left.
fn merge_pairs(heaps: List(Heap(a))) -> Heap(a) {
  pair_up(heaps, []) |> list.fold(Empty, meld)
}

fn pair_up(heaps: List(Heap(a)), acc: List(Heap(a))) -> List(Heap(a)) {
  case heaps {
    [] -> acc
    [h] -> [h, ..acc]
    [a, b, ..rest] -> pair_up(rest, [meld(a, b), ..acc])
  }
}
