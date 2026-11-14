import gleam/dict
import gleam/int
import gleam/list
import gleam/set
import gleamgraph/components
import gleamgraph/disjoint
import gleamgraph/graph.{type Graph}
import gleamgraph/mst
import gleamgraph/traverse
import testkit

pub fn disjoint_set_test() {
  let ds = disjoint.from_list([1, 2, 3, 4, 5])
  assert disjoint.count(ds) == 5
  let #(merged, ds) = disjoint.union(ds, 1, 2)
  assert merged
  let #(_, ds) = disjoint.union(ds, 4, 5)
  let #(again, ds) = disjoint.union(ds, 2, 1)
  assert !again
  assert disjoint.count(ds) == 3
  assert disjoint.connected(ds, 1, 2).0
  assert !disjoint.connected(ds, 1, 4).0
  assert disjoint.groups(ds) == [[1, 2], [3], [4, 5]]
  // Unknown elements are added on demand.
  let #(root, ds) = disjoint.find(ds, 9)
  assert root == 9
  assert disjoint.size(ds) == 6
}

pub fn disjoint_set_random_test() {
  // Compare against naive set merging.
  testkit.repeat(30, testkit.seed(41), fn(rng) {
    let #(n, rng) = testkit.between(rng, 1, 40)
    let items = testkit.range(n)
    let #(_, ds, naive) =
      testkit.repeat(
        n,
        #(rng, disjoint.from_list(items), list.map(items, fn(i) { [i] })),
        fn(state) {
          let #(rng, ds, naive) = state
          let #(a, rng) = testkit.next(rng, n)
          let #(b, rng) = testkit.next(rng, n)
          let #(with_a, others) = list.partition(naive, list.contains(_, a))
          let #(with_b, rest) = list.partition(others, list.contains(_, b))
          let naive = [
            list.flatten(list.append(with_a, with_b)) |> list.sort(int.compare),
            ..rest
          ]
          #(rng, disjoint.union(ds, a, b).1, naive)
        },
      )
    assert disjoint.groups(ds)
      == list.sort(naive, fn(x, y) { int.compare(head(x), head(y)) })
    rng
  })
}

fn head(xs: List(Int)) -> Int {
  let assert [x, ..] = xs
  x
}

pub fn components_test() {
  let g =
    graph.from_pairs(graph.Directed, [#(1, 2), #(3, 2), #(4, 5)])
    |> graph.add_node(6)
  assert components.connected_components(g) == [[1, 2, 3], [4, 5], [6]]
  assert !components.is_connected(g)
  assert components.is_connected(graph.directed())
}

pub fn scc_test() {
  let g =
    graph.from_pairs(graph.Directed, [
      #(1, 2),
      #(2, 3),
      #(3, 1),
      #(3, 4),
      #(4, 5),
      #(5, 6),
      #(6, 4),
      #(7, 6),
      #(7, 8),
      #(8, 7),
    ])
  assert components.strongly_connected_components(g)
    == [[1, 2, 3], [4, 5, 6], [7, 8]]
  let #(dag, owner) = components.condensation(g)
  assert dict.get(owner, 5) == Ok(1)
  assert graph.edges(dag)
    |> list.map(fn(e) { #(e.from, e.to) })
    |> list.sort(compare)
    == [#(0, 1), #(2, 1)]
  assert traverse.is_acyclic(dag)
}

fn compare(a: #(Int, Int), b: #(Int, Int)) {
  case a.0 == b.0 {
    True -> int.compare(a.1, b.1)
    False -> int.compare(a.0, b.0)
  }
}

pub fn scc_matches_mutual_reachability_test() {
  testkit.repeat(100, testkit.seed(42), fn(rng) {
    let #(n, rng) = testkit.between(rng, 1, 18)
    let #(m, rng) = testkit.next(rng, 35)
    let #(g, rng) = testkit.random_graph(rng, graph.Directed, n, m, 1, 1)
    let reach =
      dict.from_list(
        list.map(graph.nodes(g), fn(v) { #(v, traverse.reachable(g, v)) }),
      )
    let same = fn(a, b) {
      let assert Ok(ra) = dict.get(reach, a)
      let assert Ok(rb) = dict.get(reach, b)
      set.contains(ra, b) && set.contains(rb, a)
    }
    let expected =
      graph.nodes(g)
      |> list.map(fn(v) { list.filter(graph.nodes(g), same(v, _)) })
      |> list.unique
    assert components.strongly_connected_components(g) == expected
    let #(dag, _) = components.condensation(g)
    assert traverse.is_acyclic(dag)
    rng
  })
}

pub fn bridges_and_cut_vertices_test() {
  // Two triangles joined by the bridge 3-4, plus a pendant 6-7.
  let g =
    graph.from_pairs(graph.Undirected, [
      #(1, 2),
      #(2, 3),
      #(3, 1),
      #(3, 4),
      #(4, 5),
      #(5, 6),
      #(6, 4),
      #(6, 7),
    ])
  assert components.bridges(g) == [#(3, 4), #(6, 7)]
  assert components.articulation_points(g) == [3, 4, 6]
  // A doubled edge is not a bridge.
  let doubled = graph.from_pairs(graph.Undirected, [#(1, 2), #(1, 2), #(2, 3)])
  assert components.bridges(doubled) == [#(2, 3)]
  assert components.articulation_points(doubled) == [2]
  let cycle = graph.from_pairs(graph.Undirected, [#(0, 1), #(1, 2), #(2, 0)])
  assert components.is_biconnected(cycle)
  assert components.is_two_edge_connected(cycle)
}

fn without_edge(g: Graph, skip: Int) -> Graph {
  graph.edges(g)
  |> list.index_fold(
    graph.add_nodes(graph.undirected(), graph.nodes(g)),
    fn(acc, e, i) {
      case i == skip {
        True -> acc
        False -> graph.add_edge(acc, e.from, e.to, e.weight)
      }
    },
  )
}

pub fn bridges_match_brute_force_test() {
  testkit.repeat(120, testkit.seed(43), fn(rng) {
    let #(n, rng) = testkit.between(rng, 1, 12)
    let #(m, rng) = testkit.next(rng, 18)
    let #(g, rng) = testkit.random_graph(rng, graph.Undirected, n, m, 1, 1)
    let base = components.component_count(g)
    let expected_bridges =
      graph.edges(g)
      |> list.index_map(fn(e, i) { #(e, i) })
      |> list.filter(fn(p) {
        components.component_count(without_edge(g, p.1)) > base
      })
      |> list.map(fn(p) {
        #(int.min({ p.0 }.from, { p.0 }.to), int.max({ p.0 }.from, { p.0 }.to))
      })
      |> list.sort(compare)
    assert components.bridges(g) == expected_bridges
    let expected_cuts =
      graph.nodes(g)
      |> list.filter(fn(v) {
        let rest = list.filter(graph.nodes(g), fn(x) { x != v })
        components.component_count(graph.induced(g, rest)) > base
      })
    assert components.articulation_points(g) == expected_cuts
    rng
  })
}

pub fn mst_small_test() {
  let g =
    graph.from_edges(graph.Undirected, [
      #(0, 1, 4),
      #(0, 7, 8),
      #(1, 2, 8),
      #(1, 7, 11),
      #(2, 3, 7),
      #(2, 8, 2),
      #(2, 5, 4),
      #(3, 4, 9),
      #(3, 5, 14),
      #(4, 5, 10),
      #(5, 6, 2),
      #(6, 7, 1),
      #(6, 8, 6),
      #(7, 8, 7),
    ])
  assert mst.kruskal(g).weight == 37
  assert mst.prim(g).weight == 37
  assert list.length(mst.kruskal(g).edges) == 8
}

// Minimum weight over every edge subset that is a spanning forest.
fn brute_force_mst(g: Graph) -> Int {
  let edges = graph.edges(g)
  let target = graph.node_count(g) - components.component_count(g)
  list.combinations(edges, target)
  |> list.filter(mst.is_spanning_forest(g, _))
  |> list.map(fn(es) { list.fold(es, 0, fn(acc, e) { acc + e.weight }) })
  |> list.reduce(int.min)
  |> fn(r) {
    let assert Ok(w) = r
    w
  }
}

pub fn mst_matches_brute_force_test() {
  testkit.repeat(120, testkit.seed(44), fn(rng) {
    let #(n, rng) = testkit.between(rng, 1, 7)
    let #(m, rng) = testkit.next(rng, 11)
    let #(g, rng) = testkit.random_graph(rng, graph.Undirected, n, m, -5, 20)
    let k = mst.kruskal(g)
    let p = mst.prim(g)
    assert mst.is_spanning_forest(g, k.edges)
    assert mst.is_spanning_forest(g, p.edges)
    assert k.weight == p.weight
    assert k.weight == brute_force_mst(g)
    rng
  })
}

pub fn kruskal_prim_agree_on_larger_graphs_test() {
  testkit.repeat(40, testkit.seed(45), fn(rng) {
    let #(n, rng) = testkit.between(rng, 20, 120)
    let #(m, rng) = testkit.between(rng, n, n * 4)
    let #(g, rng) = testkit.random_graph(rng, graph.Directed, n, m, 0, 1000)
    let k = mst.kruskal(g)
    let p = mst.prim(g)
    assert k.weight == p.weight
    assert list.length(k.edges) == n - components.component_count(g)
    rng
  })
}
