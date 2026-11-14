import gleam/dict
import gleam/list
import gleamgraph/graph
import gleamgraph/shortest.{NegativeEdge, UnknownNode}
import testkit

pub fn dijkstra_small_test() {
  let g =
    graph.from_edges(graph.Directed, [
      #(0, 1, 4),
      #(0, 2, 1),
      #(2, 1, 2),
      #(1, 3, 1),
      #(2, 3, 5),
      #(4, 0, 1),
    ])
  let assert Ok(paths) = shortest.dijkstra(g, 0)
  assert shortest.distance(paths, 3) == Ok(4)
  assert shortest.path(paths, 3) == Ok([0, 2, 1, 3])
  assert shortest.path(paths, 0) == Ok([0])
  assert shortest.distance(paths, 4) == Error(Nil)
  assert shortest.path(paths, 4) == Error(Nil)
  assert shortest.shortest_path(g, 0, 3) == Ok(Ok(#(4, [0, 2, 1, 3])))
  assert shortest.shortest_path(g, 0, 4) == Ok(Error(Nil))
}

pub fn dijkstra_errors_test() {
  let g = graph.from_edges(graph.Directed, [#(0, 1, 2), #(1, 2, -1)])
  assert shortest.dijkstra(g, 0) == Error(NegativeEdge(1, 2, -1))
  assert shortest.dijkstra(g, 9) == Error(UnknownNode(9))
}

pub fn dijkstra_zero_weights_test() {
  let g =
    graph.from_edges(graph.Undirected, [#(0, 1, 0), #(1, 2, 0), #(2, 3, 3)])
  let assert Ok(paths) = shortest.dijkstra(g, 3)
  assert shortest.distance(paths, 0) == Ok(3)
}

pub fn dijkstra_matches_relaxation_test() {
  testkit.repeat(150, testkit.seed(21), fn(rng) {
    let #(n, rng) = testkit.between(rng, 1, 30)
    let #(m, rng) = testkit.next(rng, 90)
    let #(directed, rng) = testkit.next(rng, 2)
    let kind = case directed {
      0 -> graph.Directed
      _ -> graph.Undirected
    }
    let #(g, rng) = testkit.random_graph(rng, kind, n, m, 0, 20)
    let assert Ok(paths) = shortest.dijkstra(g, 0)
    let expected = testkit.relax_distances(g, 0)
    assert paths.dist == expected
    // Every reported path is real and has exactly the reported length.
    dict.each(expected, fn(node, d) {
      let assert Ok(p) = shortest.path(paths, node)
      assert list.first(p) == Ok(0)
      assert list.last(p) == Ok(node)
      assert testkit.path_weight(g, p) == Ok(d)
    })
    rng
  })
}
