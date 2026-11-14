import gleam/dict
import gleam/int
import gleam/list
import gleam/set
import gleamgraph/graph.{type Graph}
import gleamgraph/traverse
import testkit

fn sample() -> Graph {
  // 1 -> 2 -> 4, 1 -> 3 -> 4 -> 5, 6 isolated
  graph.from_pairs(graph.Directed, [#(1, 2), #(1, 3), #(2, 4), #(3, 4), #(4, 5)])
  |> graph.add_node(6)
}

pub fn bfs_order_test() {
  assert traverse.bfs(sample(), 1) == [1, 2, 3, 4, 5]
  assert traverse.bfs_layers(sample(), 1) == [[1], [2, 3], [4], [5]]
  assert traverse.bfs(sample(), 6) == [6]
  assert traverse.bfs(sample(), 42) == []
}

pub fn hop_distances_test() {
  let d = traverse.hop_distances(sample(), 1)
  assert dict.get(d, 5) == Ok(3)
  assert dict.get(d, 6) == Error(Nil)
}

pub fn dfs_order_test() {
  assert traverse.dfs(sample(), 1) == [1, 2, 4, 5, 3]
  let cyc =
    graph.from_pairs(graph.Undirected, [#(0, 1), #(1, 2), #(2, 0), #(2, 3)])
  assert traverse.dfs(cyc, 0) == [0, 1, 2, 3]
}

// A plainly recursive DFS to compare the iterative one against.
fn reference_dfs(g: Graph, node: Int, seen: List(Int)) -> List(Int) {
  case list.contains(seen, node) {
    True -> seen
    False ->
      list.fold(graph.successors(g, node), [node, ..seen], fn(seen, n) {
        reference_dfs(g, n, seen)
      })
  }
}

pub fn dfs_matches_recursive_reference_test() {
  testkit.repeat(60, testkit.seed(3), fn(rng) {
    let #(n, rng) = testkit.between(rng, 1, 25)
    let #(m, rng) = testkit.next(rng, 60)
    let #(g, rng) = testkit.random_graph(rng, graph.Directed, n, m, 1, 1)
    assert traverse.dfs(g, 0) == list.reverse(reference_dfs(g, 0, []))
    // BFS and DFS reach the same nodes.
    assert set.from_list(traverse.bfs(g, 0)) == traverse.reachable(g, 0)
    rng
  })
}

pub fn topological_sort_small_test() {
  assert traverse.topological_sort(sample()) == Ok([1, 2, 3, 4, 5, 6])
  let g = graph.from_pairs(graph.Directed, [#(5, 1), #(1, 0), #(5, 0), #(3, 1)])
  assert traverse.topological_sort(g) == Ok([3, 5, 1, 0])
}

pub fn topological_sort_reports_cycle_test() {
  let g =
    graph.from_pairs(graph.Directed, [
      #(0, 1),
      #(1, 2),
      #(2, 3),
      #(3, 1),
      #(3, 4),
    ])
  assert traverse.topological_sort(g) == Error([1, 2, 3])
  assert !traverse.is_acyclic(g)
  let loop = graph.from_pairs(graph.Directed, [#(7, 7)])
  assert traverse.topological_sort(loop) == Error([7])
}

fn respects_edges(g: Graph, order: List(Int)) -> Bool {
  let position = dict.from_list(list.index_map(order, fn(n, i) { #(n, i) }))
  list.all(graph.edges(g), fn(e) {
    let assert Ok(a) = dict.get(position, e.from)
    let assert Ok(b) = dict.get(position, e.to)
    a < b
  })
}

fn is_cycle(g: Graph, cycle: List(Int)) -> Bool {
  let assert [first, ..] = cycle
  let closed = list.append(cycle, [first])
  list.window_by_2(closed) |> list.all(fn(p) { graph.has_edge(g, p.0, p.1) })
}

pub fn random_dags_sort_test() {
  testkit.repeat(80, testkit.seed(11), fn(rng) {
    let #(n, rng) = testkit.between(rng, 1, 40)
    let #(m, rng) = testkit.next(rng, 120)
    let #(g, rng) = testkit.random_dag(rng, n, m)
    let assert Ok(order) = traverse.topological_sort(g)
    assert list.sort(order, int.compare) == graph.nodes(g)
    assert respects_edges(g, order)
    rng
  })
}

pub fn random_digraphs_sort_or_cycle_test() {
  testkit.repeat(120, testkit.seed(12), fn(rng) {
    let #(n, rng) = testkit.between(rng, 1, 15)
    let #(m, rng) = testkit.next(rng, 25)
    let #(g, rng) = testkit.random_graph(rng, graph.Directed, n, m, 1, 1)
    case traverse.topological_sort(g) {
      Ok(order) -> {
        assert respects_edges(g, order)
      }
      Error(cycle) -> {
        assert is_cycle(g, cycle)
        assert list.length(list.unique(cycle)) == list.length(cycle)
      }
    }
    rng
  })
}
