import gleamgraph/graph.{Edge}

pub fn empty_graph_test() {
  let g = graph.directed()
  assert graph.node_count(g) == 0
  assert graph.edge_count(g) == 0
  assert graph.nodes(g) == []
  assert graph.neighbors(g, 1) == []
}

pub fn directed_edges_test() {
  let g = graph.from_edges(graph.Directed, [#(1, 2, 5), #(1, 3, 2), #(3, 2, 1)])
  assert graph.nodes(g) == [1, 2, 3]
  assert graph.neighbors(g, 1) == [#(2, 5), #(3, 2)]
  assert graph.neighbors(g, 2) == []
  assert graph.has_edge(g, 1, 2)
  assert !graph.has_edge(g, 2, 1)
  assert graph.edges(g) == [Edge(1, 2, 5), Edge(1, 3, 2), Edge(3, 2, 1)]
  assert graph.total_weight(g) == 8
}

pub fn undirected_edges_test() {
  let g = graph.from_pairs(graph.Undirected, [#(1, 2), #(2, 3), #(3, 3)])
  assert graph.successors(g, 2) == [1, 3]
  assert graph.successors(g, 3) == [2, 3]
  assert graph.edge_count(g) == 3
  assert graph.arcs(g)
    == [
      Edge(1, 2, 1),
      Edge(2, 1, 1),
      Edge(2, 3, 1),
      Edge(3, 2, 1),
      Edge(3, 3, 1),
    ]
}

pub fn parallel_edges_test() {
  let g = graph.from_edges(graph.Directed, [#(0, 1, 4), #(0, 1, 7)])
  assert graph.edge_count(g) == 2
  assert graph.out_degree(g, 0) == 2
}

pub fn reverse_test() {
  let g =
    graph.from_edges(graph.Directed, [#(1, 2, 5), #(2, 3, 1)])
    |> graph.add_node(9)
  let r = graph.reverse(g)
  assert graph.nodes(r) == [1, 2, 3, 9]
  assert graph.neighbors(r, 3) == [#(2, 1)]
  assert graph.neighbors(r, 2) == [#(1, 5)]
}

pub fn induced_test() {
  let g = graph.from_pairs(graph.Directed, [#(1, 2), #(2, 3), #(3, 1), #(3, 4)])
  let sub = graph.induced(g, [1, 2, 3, 7])
  assert graph.nodes(sub) == [1, 2, 3]
  assert graph.edge_count(sub) == 3
}

pub fn map_weights_and_undirected_test() {
  let g = graph.from_edges(graph.Directed, [#(1, 2, 5), #(2, 3, 1)])
  let doubled = graph.map_weights(g, fn(e) { e.weight * 2 })
  assert graph.total_weight(doubled) == 12
  let u = graph.to_undirected(g)
  assert graph.successors(u, 2) == [1, 3]
}
