import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleamgraph/flow.{NegativeCapacity, SourceIsSink, UnknownNode}
import gleamgraph/graph.{type Graph}
import gleamgraph/matching
import testkit

fn clrs() -> Graph {
  graph.from_edges(graph.Directed, [
    #(0, 1, 16),
    #(0, 2, 13),
    #(1, 3, 12),
    #(2, 1, 4),
    #(2, 4, 14),
    #(3, 2, 9),
    #(3, 5, 20),
    #(4, 3, 7),
    #(4, 5, 4),
  ])
}

pub fn clrs_network_test() {
  let assert Ok(f) = flow.max_flow(clrs(), 0, 5)
  assert f.value == 23
  assert f.source_side == [0, 1, 2, 4]
  assert f.cut == [#(1, 3), #(4, 3), #(4, 5)]
}

pub fn flow_errors_test() {
  assert flow.max_flow(clrs(), 0, 0) == Error(SourceIsSink)
  assert flow.max_flow(clrs(), 0, 9) == Error(UnknownNode(9))
  let bad = graph.from_edges(graph.Directed, [#(0, 1, -2)])
  assert flow.max_flow(bad, 0, 1) == Error(NegativeCapacity(0, 1, -2))
}

pub fn disconnected_and_parallel_test() {
  let g = graph.from_edges(graph.Directed, [#(0, 1, 3), #(0, 1, 4), #(2, 3, 9)])
  let assert Ok(f) = flow.max_flow(g, 0, 1)
  assert f.value == 7
  let assert Ok(none) = flow.max_flow(g, 0, 3)
  assert none.value == 0
  assert none.cut == []
}

pub fn undirected_capacity_test() {
  let g =
    graph.from_edges(graph.Undirected, [#(0, 1, 5), #(1, 2, 3), #(0, 2, 1)])
  let assert Ok(f) = flow.max_flow(g, 2, 0)
  assert f.value == 4
}

fn check_flow(g: Graph, s: Int, t: Int, f: flow.MaxFlow) -> Nil {
  let cap = flow.capacities(g)
  // Capacity constraints.
  dict.each(f.flows, fn(pair, amount) {
    assert amount > 0
    assert amount <= result.unwrap(dict.get(cap, pair), 0)
  })
  // Conservation everywhere except source and sink.
  let balance = net_out(f.flows)
  list.each(graph.nodes(g), fn(v) {
    let b = result.unwrap(dict.get(balance, v), 0)
    case v == s, v == t {
      True, _ -> {
        assert b == f.value
      }
      _, True -> {
        assert b == -f.value
      }
      _, _ -> {
        assert b == 0
      }
    }
  })
  // The cut is saturated and its capacity equals the flow value.
  let cut_capacity =
    list.fold(f.cut, 0, fn(acc, pair) {
      acc + result.unwrap(dict.get(cap, pair), 0)
    })
  assert cut_capacity == f.value
  assert list.contains(f.source_side, s)
  assert !list.contains(f.source_side, t)
}

fn net_out(flows: Dict(#(Int, Int), Int)) -> Dict(Int, Int) {
  dict.fold(flows, dict.new(), fn(acc, pair, amount) {
    acc
    |> dict.insert(pair.0, result.unwrap(dict.get(acc, pair.0), 0) + amount)
    |> fn(acc) {
      dict.insert(acc, pair.1, result.unwrap(dict.get(acc, pair.1), 0) - amount)
    }
  })
}

// Minimum over every s-t cut of the capacity leaving the source side.
fn brute_force_min_cut(g: Graph, s: Int, t: Int) -> Int {
  let cap = flow.capacities(g)
  let others = list.filter(graph.nodes(g), fn(v) { v != s && v != t })
  subsets(others)
  |> list.map(fn(side) {
    let side = [s, ..side]
    dict.fold(cap, 0, fn(acc, pair, c) {
      case list.contains(side, pair.0) && !list.contains(side, pair.1) {
        True -> acc + c
        False -> acc
      }
    })
  })
  |> list.reduce(int.min)
  |> result.unwrap(0)
}

fn subsets(items: List(Int)) -> List(List(Int)) {
  case items {
    [] -> [[]]
    [x, ..rest] -> {
      let tails = subsets(rest)
      list.append(tails, list.map(tails, fn(t) { [x, ..t] }))
    }
  }
}

pub fn max_flow_equals_min_cut_test() {
  testkit.repeat(150, testkit.seed(51), fn(rng) {
    let #(n, rng) = testkit.between(rng, 2, 9)
    let #(m, rng) = testkit.next(rng, 22)
    let #(directed, rng) = testkit.next(rng, 3)
    let kind = case directed {
      0 -> graph.Undirected
      _ -> graph.Directed
    }
    let #(g, rng) = testkit.random_graph(rng, kind, n, m, 0, 10)
    let #(t, rng) = testkit.between(rng, 1, n - 1)
    let assert Ok(f) = flow.max_flow(g, 0, t)
    check_flow(g, 0, t, f)
    assert f.value == brute_force_min_cut(g, 0, t)
    rng
  })
}

pub fn bipartition_test() {
  let even =
    graph.from_pairs(graph.Undirected, [#(1, 2), #(2, 3), #(3, 4), #(4, 1)])
  assert matching.bipartition(even) == Ok(#([1, 3], [2, 4]))
  let odd = graph.from_pairs(graph.Undirected, [#(1, 2), #(2, 3), #(3, 1)])
  assert matching.bipartition(odd) == Error(Nil)
  assert !matching.is_bipartite(graph.from_pairs(graph.Directed, [#(5, 5)]))
}

pub fn matching_small_test() {
  let g =
    graph.from_pairs(graph.Undirected, [
      #(1, 10),
      #(1, 11),
      #(2, 10),
      #(3, 11),
      #(3, 12),
      #(4, 12),
      #(4, 13),
    ])
  assert matching.bipartite_matching(g, [1, 2, 3, 4])
    == [#(1, 11), #(2, 10), #(3, 12), #(4, 13)]
  let assert Ok(pairs) = matching.maximum_matching(g)
  assert list.length(pairs) == 4
}

fn is_matching(g: Graph, pairs: List(#(Int, Int))) -> Bool {
  let used = list.flat_map(pairs, fn(p) { [p.0, p.1] })
  list.length(list.unique(used)) == list.length(used)
  && list.all(pairs, fn(p) { graph.has_edge(g, p.0, p.1) })
}

fn brute_force_matching(edges: List(#(Int, Int))) -> Int {
  case edges {
    [] -> 0
    [#(a, b), ..rest] -> {
      let skip = brute_force_matching(rest)
      let take =
        1
        + brute_force_matching(
          list.filter(rest, fn(e) {
            e.0 != a && e.0 != b && e.1 != a && e.1 != b
          }),
        )
      int.max(skip, take)
    }
  }
}

pub fn matching_matches_brute_force_and_flow_test() {
  testkit.repeat(150, testkit.seed(52), fn(rng) {
    let #(left, rng) = testkit.between(rng, 1, 7)
    let #(right, rng) = testkit.between(rng, 1, 7)
    let #(m, rng) = testkit.next(rng, 16)
    let #(pairs, rng) =
      testkit.repeat(m, #([], rng), fn(state) {
        let #(acc, rng) = state
        let #(a, rng) = testkit.next(rng, left)
        let #(b, rng) = testkit.next(rng, right)
        #([#(a, 100 + b), ..acc], rng)
      })
    let g =
      graph.from_pairs(graph.Undirected, pairs)
      |> graph.add_nodes(testkit.range(left))
    let found = matching.bipartite_matching(g, testkit.range(left))
    assert is_matching(g, found)
    assert list.length(found) == brute_force_matching(list.unique(pairs))
    // Same answer as unit-capacity max flow from a super source to a super sink.
    let network =
      graph.from_pairs(
        graph.Directed,
        list.flatten([
          list.unique(pairs),
          list.map(testkit.range(left), fn(a) { #(-1, a) }),
          list.map(testkit.range(right), fn(b) { #(100 + b, -2) }),
        ]),
      )
    let assert Ok(f) = flow.max_flow(network, -1, -2)
    assert f.value == list.length(found)
    rng
  })
}
