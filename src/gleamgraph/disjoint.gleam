//// A persistent union-find (disjoint-set forest) with union by rank and
//// path compression. Operations that may compress paths return the
//// updated structure alongside their answer.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}

pub opaque type DisjointSet {
  DisjointSet(parent: Dict(Int, Int), rank: Dict(Int, Int), count: Int)
}

pub fn new() -> DisjointSet {
  DisjointSet(dict.new(), dict.new(), 0)
}

/// One singleton set per element.
pub fn from_list(items: List(Int)) -> DisjointSet {
  list.fold(items, new(), add)
}

/// Add `x` as a singleton set (no-op if already present).
pub fn add(ds: DisjointSet, x: Int) -> DisjointSet {
  case dict.has_key(ds.parent, x) {
    True -> ds
    False ->
      DisjointSet(
        parent: dict.insert(ds.parent, x, x),
        rank: dict.insert(ds.rank, x, 0),
        count: ds.count + 1,
      )
  }
}

/// The representative of `x`'s set. Unknown elements are added first.
pub fn find(ds: DisjointSet, x: Int) -> #(Int, DisjointSet) {
  let ds = add(ds, x)
  let #(root, parent) = find_root(ds.parent, x)
  #(root, DisjointSet(..ds, parent:))
}

fn find_root(parent: Dict(Int, Int), x: Int) -> #(Int, Dict(Int, Int)) {
  let assert Ok(p) = dict.get(parent, x)
  case p == x {
    True -> #(x, parent)
    False -> {
      let #(root, parent) = find_root(parent, p)
      #(root, dict.insert(parent, x, root))
    }
  }
}

/// Merge the sets containing `a` and `b`. Returns `True` if they were
/// different sets.
pub fn union(ds: DisjointSet, a: Int, b: Int) -> #(Bool, DisjointSet) {
  let #(ra, ds) = find(ds, a)
  let #(rb, ds) = find(ds, b)
  case ra == rb {
    True -> #(False, ds)
    False -> {
      let assert Ok(rank_a) = dict.get(ds.rank, ra)
      let assert Ok(rank_b) = dict.get(ds.rank, rb)
      let #(child, root) = case rank_a < rank_b {
        True -> #(ra, rb)
        False -> #(rb, ra)
      }
      let rank = case rank_a == rank_b {
        True -> dict.insert(ds.rank, root, rank_a + 1)
        False -> ds.rank
      }
      #(
        True,
        DisjointSet(
          parent: dict.insert(ds.parent, child, root),
          rank:,
          count: ds.count - 1,
        ),
      )
    }
  }
}

/// Are `a` and `b` in the same set?
pub fn connected(ds: DisjointSet, a: Int, b: Int) -> #(Bool, DisjointSet) {
  let #(ra, ds) = find(ds, a)
  let #(rb, ds) = find(ds, b)
  #(ra == rb, ds)
}

/// Number of disjoint sets.
pub fn count(ds: DisjointSet) -> Int {
  ds.count
}

/// Number of elements.
pub fn size(ds: DisjointSet) -> Int {
  dict.size(ds.parent)
}

/// The sets, each sorted, ordered by their smallest element.
pub fn groups(ds: DisjointSet) -> List(List(Int)) {
  let #(by_root, _) =
    dict.keys(ds.parent)
    |> list.fold(#(dict.new(), ds), fn(state, x) {
      let #(acc, ds) = state
      let #(root, ds) = find(ds, x)
      #(
        dict.upsert(acc, root, fn(m) {
          case m {
            Some(xs) -> [x, ..xs]
            None -> [x]
          }
        }),
        ds,
      )
    })
  dict.values(by_root)
  |> list.map(list.sort(_, int.compare))
  |> list.sort(fn(a, b) { int.compare(first(a), first(b)) })
}

fn first(xs: List(Int)) -> Int {
  case xs {
    [x, ..] -> x
    [] -> 0
  }
}
