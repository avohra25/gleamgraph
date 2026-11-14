//// Deterministic helpers shared by the test modules: a seeded PRNG,
//// random graph generators and slow-but-obvious reference algorithms.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleamgraph/graph.{type Graph, type Kind}

/// A 31-bit linear congruential generator (glibc constants). Good enough
/// for generating test cases and fully reproducible.
pub type Rng {
  Rng(state: Int)
}

pub fn seed(n: Int) -> Rng {
  Rng(n % 2_147_483_648)
}

/// A value in `0..bound-1` and the next generator.
pub fn next(rng: Rng, bound: Int) -> #(Int, Rng) {
  let state = { rng.state * 1_103_515_245 + 12_345 } % 2_147_483_648
  #({ state / 65_536 } % bound, Rng(state))
}

/// A value in `low..high` inclusive.
pub fn between(rng: Rng, low: Int, high: Int) -> #(Int, Rng) {
  let #(x, rng) = next(rng, high - low + 1)
  #(low + x, rng)
}

/// A random graph on nodes `0..n-1` with `m` edges and weights in
/// `low..high`. Every node is present even if isolated.
pub fn random_graph(
  rng: Rng,
  kind: Kind,
  n: Int,
  m: Int,
  low: Int,
  high: Int,
) -> #(Graph, Rng) {
  let base = graph.new(kind) |> graph.add_nodes(range(n))
  repeat(m, #(base, rng), fn(state) {
    let #(g, rng) = state
    let #(a, rng) = next(rng, n)
    let #(b, rng) = next(rng, n)
    let #(w, rng) = between(rng, low, high)
    #(graph.add_edge(g, a, b, w), rng)
  })
}

/// A random DAG: every edge goes from a lower to a higher id under a
/// random relabelling, so the true order is hidden.
pub fn random_dag(rng: Rng, n: Int, m: Int) -> #(Graph, Rng) {
  let #(perm, rng) = shuffle(rng, range(n))
  let label = dict.from_list(list.index_map(perm, fn(p, i) { #(i, p) }))
  let base = graph.directed() |> graph.add_nodes(perm)
  repeat(m, #(base, rng), fn(state) {
    let #(g, rng) = state
    let #(a, rng) = next(rng, n)
    let #(b, rng) = next(rng, n)
    case a == b {
      True -> #(g, rng)
      False -> {
        let #(lo, hi) = #(int.min(a, b), int.max(a, b))
        let assert Ok(x) = dict.get(label, lo)
        let assert Ok(y) = dict.get(label, hi)
        #(graph.add_edge(g, x, y, 1), rng)
      }
    }
  })
}

pub fn range(n: Int) -> List(Int) {
  int.range(n - 1, -1, [], fn(acc, i) { [i, ..acc] })
}

pub fn shuffle(rng: Rng, items: List(a)) -> #(List(a), Rng) {
  let #(keyed, rng) =
    list.fold(items, #([], rng), fn(state, item) {
      let #(acc, rng) = state
      let #(k, rng) = next(rng, 1_000_000)
      #([#(k, item), ..acc], rng)
    })
  #(
    keyed
      |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
      |> list.map(fn(p) { p.1 }),
    rng,
  )
}

pub fn repeat(times: Int, state: a, f: fn(a) -> a) -> a {
  case times <= 0 {
    True -> state
    False -> repeat(times - 1, f(state), f)
  }
}

/// Reference shortest distances by repeated relaxation of every arc until
/// nothing changes (no negative cycles assumed).
pub fn relax_distances(g: Graph, source: Int) -> Dict(Int, Int) {
  relax_until_stable(g, dict.from_list([#(source, 0)]))
}

fn relax_until_stable(g: Graph, dist: Dict(Int, Int)) -> Dict(Int, Int) {
  let next =
    list.fold(graph.arcs(g), dist, fn(dist, e) {
      case dict.get(dist, e.from) {
        Error(Nil) -> dist
        Ok(du) ->
          case dict.get(dist, e.to) {
            Ok(dv) if dv <= du + e.weight -> dist
            _ -> dict.insert(dist, e.to, du + e.weight)
          }
      }
    })
  case next == dist {
    True -> dist
    False -> relax_until_stable(g, next)
  }
}

/// Weight of the lightest arc `from -> to`, if any.
pub fn arc_weight(g: Graph, from: Int, to: Int) -> Result(Int, Nil) {
  graph.neighbors(g, from)
  |> list.filter(fn(n) { n.0 == to })
  |> list.map(fn(n) { n.1 })
  |> list.reduce(int.min)
}

/// Total weight of a path, or Error if some step is not an arc.
pub fn path_weight(g: Graph, path: List(Int)) -> Result(Int, Nil) {
  case path {
    [] | [_] -> Ok(0)
    [a, b, ..rest] ->
      case arc_weight(g, a, b), path_weight(g, [b, ..rest]) {
        Ok(w), Ok(tail) -> Ok(w + tail)
        _, _ -> Error(Nil)
      }
  }
}
