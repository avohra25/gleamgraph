//// Maximum flow and minimum cut with the Edmonds-Karp algorithm
//// (shortest augmenting paths), O(V E^2). Edge weights are capacities;
//// parallel edges add up and an undirected edge has its capacity in both
//// directions.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleamgraph/graph.{type Graph}

pub type MaxFlow {
  MaxFlow(
    /// Total flow from source to sink.
    value: Int,
    /// Net positive flow on each node pair that carries any.
    flows: Dict(#(Int, Int), Int),
    /// Nodes on the source side of a minimum cut, sorted.
    source_side: List(Int),
    /// Saturated pairs crossing the minimum cut; their capacities sum to
    /// `value`.
    cut: List(#(Int, Int)),
  )
}

pub type FlowError {
  UnknownNode(node: Int)
  SourceIsSink
  NegativeCapacity(from: Int, to: Int, capacity: Int)
}

type Network {
  Network(cap: Dict(#(Int, Int), Int), adj: Dict(Int, List(Int)))
}

/// Capacity between two nodes after merging parallel edges.
pub fn capacities(g: Graph) -> Dict(#(Int, Int), Int) {
  list.fold(graph.arcs(g), dict.new(), fn(acc, e) {
    case e.from == e.to {
      True -> acc
      False ->
        dict.upsert(acc, #(e.from, e.to), fn(c) {
          option.unwrap(c, 0) + e.weight
        })
    }
  })
}

pub fn max_flow(
  g: Graph,
  source: Int,
  sink: Int,
) -> Result(MaxFlow, FlowError) {
  use _ <- result.try(known(g, source))
  use _ <- result.try(known(g, sink))
  use _ <- result.try(case source == sink {
    True -> Error(SourceIsSink)
    False -> Ok(Nil)
  })
  use _ <- result.try(case list.find(graph.edges(g), fn(e) { e.weight < 0 }) {
    Ok(e) -> Error(NegativeCapacity(e.from, e.to, e.weight))
    Error(Nil) -> Ok(Nil)
  })
  let cap = capacities(g)
  let adj =
    dict.fold(cap, dict.new(), fn(acc, pair, _) {
      acc |> add_neighbor(pair.0, pair.1) |> add_neighbor(pair.1, pair.0)
    })
    |> dict.map_values(fn(_, ns) { list.unique(list.reverse(ns)) })
  let #(residual, value) = augment(Network(cap, adj), source, sink, cap, 0)
  let flows =
    dict.fold(cap, dict.new(), fn(acc, pair, c) {
      let net = c - residual_of(residual, pair)
      case net > 0 {
        True -> dict.insert(acc, pair, net)
        False -> acc
      }
    })
  let side =
    reach(Network(cap, adj), residual, [source], set.from_list([source]))
  let cut =
    dict.keys(cap)
    |> list.filter(fn(pair) {
      set.contains(side, pair.0) && !set.contains(side, pair.1)
    })
    |> list.sort(compare_pairs)
  Ok(MaxFlow(
    value:,
    flows:,
    source_side: set.to_list(side) |> list.sort(int.compare),
    cut:,
  ))
}

fn known(g: Graph, node: Int) -> Result(Nil, FlowError) {
  case graph.has_node(g, node) {
    True -> Ok(Nil)
    False -> Error(UnknownNode(node))
  }
}

fn add_neighbor(adj: Dict(Int, List(Int)), a: Int, b: Int) {
  dict.upsert(adj, a, fn(ns) {
    case ns {
      Some(ns) -> [b, ..ns]
      None -> [b]
    }
  })
}

fn residual_of(residual: Dict(#(Int, Int), Int), pair: #(Int, Int)) -> Int {
  result.unwrap(dict.get(residual, pair), 0)
}

fn augment(
  net: Network,
  source: Int,
  sink: Int,
  residual: Dict(#(Int, Int), Int),
  value: Int,
) -> #(Dict(#(Int, Int), Int), Int) {
  case
    bfs_path(
      net,
      residual,
      sink,
      [source],
      [],
      dict.from_list([#(source, source)]),
    )
  {
    Error(Nil) -> #(residual, value)
    Ok(parent) -> {
      let path = walk(parent, source, sink, [])
      let bottleneck =
        list.fold(path, -1, fn(acc, pair) {
          let r = residual_of(residual, pair)
          case acc < 0 || r < acc {
            True -> r
            False -> acc
          }
        })
      let residual =
        list.fold(path, residual, fn(res, pair) {
          res
          |> dict.insert(pair, residual_of(res, pair) - bottleneck)
          |> dict.insert(
            #(pair.1, pair.0),
            residual_of(res, #(pair.1, pair.0)) + bottleneck,
          )
        })
      augment(net, source, sink, residual, value + bottleneck)
    }
  }
}

// Breadth-first search over positive-residual pairs, level by level.
fn bfs_path(
  net: Network,
  residual: Dict(#(Int, Int), Int),
  sink: Int,
  frontier: List(Int),
  next: List(Int),
  parent: Dict(Int, Int),
) -> Result(Dict(Int, Int), Nil) {
  case dict.has_key(parent, sink), frontier, next {
    True, _, _ -> Ok(parent)
    False, [], [] -> Error(Nil)
    False, [], _ ->
      bfs_path(net, residual, sink, list.reverse(next), [], parent)
    False, [u, ..rest], _ -> {
      let #(next, parent) =
        list.fold(neighbors(net, u), #(next, parent), fn(state, v) {
          let #(next, parent) = state
          case dict.has_key(parent, v) || residual_of(residual, #(u, v)) <= 0 {
            True -> state
            False -> #([v, ..next], dict.insert(parent, v, u))
          }
        })
      bfs_path(net, residual, sink, rest, next, parent)
    }
  }
}

fn neighbors(net: Network, u: Int) -> List(Int) {
  result.unwrap(dict.get(net.adj, u), [])
}

fn walk(
  parent: Dict(Int, Int),
  source: Int,
  node: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case node == source {
    True -> acc
    False -> {
      let assert Ok(p) = dict.get(parent, node)
      walk(parent, source, p, [#(p, node), ..acc])
    }
  }
}

fn reach(
  net: Network,
  residual: Dict(#(Int, Int), Int),
  stack: List(Int),
  seen: Set(Int),
) -> Set(Int) {
  case stack {
    [] -> seen
    [u, ..rest] -> {
      let fresh =
        neighbors(net, u)
        |> list.filter(fn(v) {
          !set.contains(seen, v) && residual_of(residual, #(u, v)) > 0
        })
      reach(
        net,
        residual,
        list.append(fresh, rest),
        list.fold(fresh, seen, set.insert),
      )
    }
  }
}

fn compare_pairs(a: #(Int, Int), b: #(Int, Int)) {
  case int.compare(a.0, b.0) {
    order.Eq -> int.compare(a.1, b.1)
    other -> other
  }
}
