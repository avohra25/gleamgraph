import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleamgraph/graph.{type Graph}
import gleamgraph/shortest.{NegativeCycle, NotAcyclic}
import testkit

pub fn bellman_ford_small_test() {
  let g =
    graph.from_edges(graph.Directed, [
      #(0, 1, 4),
      #(0, 2, 5),
      #(1, 2, -3),
      #(2, 3, 4),
      #(3, 1, 2),
    ])
  let assert Ok(paths) = shortest.bellman_ford(g, 0)
  assert shortest.distance(paths, 2) == Ok(1)
  assert shortest.distance(paths, 3) == Ok(5)
  assert shortest.path(paths, 3) == Ok([0, 1, 2, 3])
}

pub fn bellman_ford_cycle_witness_test() {
  let g =
    graph.from_edges(graph.Directed, [
      #(0, 1, 1),
      #(1, 2, -1),
      #(2, 3, -1),
      #(3, 1, -1),
      #(3, 4, 1),
    ])
  assert shortest.bellman_ford(g, 0) == Error(NegativeCycle([1, 2, 3]))
  // The same cycle is invisible from a node that cannot reach it.
  let assert Ok(_) = shortest.bellman_ford(g, 4)
}

pub fn undirected_negative_edge_is_cycle_test() {
  let g = graph.from_edges(graph.Undirected, [#(0, 1, 2), #(1, 2, -1)])
  assert shortest.bellman_ford(g, 0) == Error(NegativeCycle([1, 2]))
}

pub fn dag_paths_test() {
  let g =
    graph.from_edges(graph.Directed, [
      #(0, 1, 5),
      #(0, 2, 3),
      #(1, 3, 6),
      #(1, 2, 2),
      #(2, 4, 4),
      #(2, 5, 2),
      #(2, 3, 7),
      #(3, 4, -1),
      #(4, 5, -2),
    ])
  let assert Ok(paths) = shortest.dag_paths(g, 1)
  assert shortest.distance(paths, 5) == Ok(3)
  assert shortest.path(paths, 5) == Ok([1, 3, 4, 5])
  assert shortest.distance(paths, 0) == Error(Nil)
  let cyclic = graph.from_pairs(graph.Directed, [#(0, 1), #(1, 0)])
  assert shortest.dag_paths(cyclic, 0) == Error(NotAcyclic([0, 1]))
}

// Reference: relax every arc n rounds; if the last round still changed
// something, a negative cycle is reachable.
fn reference(g: Graph, source: Int) -> Result(Dict(Int, Int), Nil) {
  let start = dict.from_list([#(source, 0)])
  let #(dist, changed) =
    testkit.repeat(graph.node_count(g), #(start, False), fn(state) {
      let next = relax(g, state.0)
      #(next, next != state.0)
    })
  case changed {
    True -> Error(Nil)
    False -> Ok(dist)
  }
}

fn relax(g: Graph, dist: Dict(Int, Int)) -> Dict(Int, Int) {
  list.fold(graph.arcs(g), dist, fn(dist, e) {
    case dict.get(dist, e.from), dict.get(dist, e.to) {
      Ok(du), Ok(dv) if dv <= du + e.weight -> dist
      Ok(du), _ -> dict.insert(dist, e.to, du + e.weight)
      Error(Nil), _ -> dist
    }
  })
}

fn closed_weight(g: Graph, cycle: List(Int)) -> Int {
  let assert [first, ..] = cycle
  let assert Ok(w) = testkit.path_weight(g, list.append(cycle, [first]))
  w
}

pub fn bellman_ford_matches_reference_test() {
  testkit.repeat(250, testkit.seed(31), fn(rng) {
    let #(n, rng) = testkit.between(rng, 1, 14)
    let #(m, rng) = testkit.next(rng, 30)
    let #(g, rng) = testkit.random_graph(rng, graph.Directed, n, m, -4, 12)
    case shortest.bellman_ford(g, 0), reference(g, 0) {
      Ok(paths), Ok(expected) -> {
        assert paths.dist == expected
        dict.each(expected, fn(node, d) {
          let assert Ok(p) = shortest.path(paths, node)
          assert testkit.path_weight(g, p) == Ok(d)
        })
      }
      Error(NegativeCycle(cycle)), Error(Nil) -> {
        assert closed_weight(g, cycle) < 0
        assert list.unique(cycle) == cycle
      }
      _, _ -> panic as "Bellman-Ford disagrees with the reference"
    }
    rng
  })
}

pub fn dag_paths_match_bellman_ford_test() {
  testkit.repeat(80, testkit.seed(32), fn(rng) {
    let #(n, rng) = testkit.between(rng, 1, 30)
    let #(m, rng) = testkit.next(rng, 80)
    let #(dag, rng) = testkit.random_dag(rng, n, m)
    let #(seed, rng) = testkit.next(rng, 100_000)
    let weighted =
      graph.map_weights(dag, fn(e) {
        { e.from * 31 + e.to * 17 + seed } % 21 - 10
      })
    let assert [source, ..] = graph.nodes(weighted)
    let assert Ok(a) = shortest.dag_paths(weighted, source)
    let assert Ok(b) = shortest.bellman_ford(weighted, source)
    assert a.dist == b.dist
    rng
  })
}

pub fn floyd_warshall_matches_bellman_ford_test() {
  testkit.repeat(60, testkit.seed(33), fn(rng) {
    let #(n, rng) = testkit.between(rng, 1, 12)
    let #(m, rng) = testkit.next(rng, 30)
    let #(g, rng) = testkit.random_graph(rng, graph.Directed, n, m, -2, 15)
    let any_cycle =
      list.any(graph.nodes(g), fn(v) {
        case shortest.bellman_ford(g, v) {
          Error(_) -> True
          Ok(_) -> False
        }
      })
    case shortest.floyd_warshall(g) {
      Error(NegativeCycle(cycle)) -> {
        assert any_cycle
        assert closed_weight(g, cycle) < 0
      }
      Error(_) -> panic as "unexpected error"
      Ok(all) -> {
        assert !any_cycle
        list.each(graph.nodes(g), fn(s) {
          let assert Ok(paths) = shortest.bellman_ford(g, s)
          dict.each(paths.dist, fn(t, d) {
            assert dict.get(all, #(s, t)) == Ok(d)
          })
          let from_s = dict.filter(all, fn(k, _) { k.0 == s })
          assert dict.size(from_s) == dict.size(paths.dist)
        })
      }
    }
    rng
  })
}

fn grid(rng: testkit.Rng, w: Int, h: Int) -> #(Graph, testkit.Rng) {
  testkit.range(w * h)
  |> list.fold(#(graph.undirected(), rng), fn(state, id) {
    let #(g, rng) = state
    let #(right, rng) = testkit.between(rng, 1, 9)
    let #(down, rng) = testkit.between(rng, 1, 9)
    let g = case id % w < w - 1 {
      True -> graph.add_edge(g, id, id + 1, right)
      False -> graph.add_node(g, id)
    }
    let g = case id / w < h - 1 {
      True -> graph.add_edge(g, id, id + w, down)
      False -> g
    }
    #(g, rng)
  })
}

pub fn astar_matches_dijkstra_on_grids_test() {
  testkit.repeat(40, testkit.seed(34), fn(rng) {
    let #(w, rng) = testkit.between(rng, 1, 12)
    let #(h, rng) = testkit.between(rng, 1, 12)
    let #(g, rng) = grid(rng, w, h)
    let #(s, rng) = testkit.next(rng, w * h)
    let #(t, rng) = testkit.next(rng, w * h)
    let manhattan = fn(v) {
      int.absolute_value(v % w - t % w) + int.absolute_value(v / w - t / w)
    }
    let assert Ok(Ok(#(d, _))) = shortest.shortest_path(g, s, t)
    let assert Ok(Ok(#(d1, p1))) = shortest.astar(g, s, t, manhattan)
    let assert Ok(Ok(#(d0, _))) = shortest.astar(g, s, t, fn(_) { 0 })
    assert d1 == d
    assert d0 == d
    assert testkit.path_weight(g, p1) == Ok(d)
    rng
  })
}

pub fn astar_unreachable_test() {
  let g = graph.from_edges(graph.Directed, [#(0, 1, 1)]) |> graph.add_node(2)
  assert shortest.astar(g, 0, 2, fn(_) { 0 }) == Ok(Error(Nil))
}
