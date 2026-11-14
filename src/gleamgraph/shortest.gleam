//// Single-source shortest paths.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleamgraph/graph.{type Graph}
import gleamgraph/heap
import gleamgraph/traverse

/// A shortest-path tree rooted at `source`. Nodes that are unreachable from
/// the source have no entry in `dist` or `pred`.
pub type Paths {
  Paths(source: Int, dist: Dict(Int, Int), pred: Dict(Int, Int))
}

pub type PathError {
  /// The source node is not in the graph.
  UnknownNode(node: Int)
  /// Dijkstra and A* require non-negative weights.
  NegativeEdge(from: Int, to: Int, weight: Int)
  /// A negative-weight cycle `v0 -> v1 -> ... -> vk -> v0`.
  NegativeCycle(cycle: List(Int))
  /// `dag_paths` was given a graph containing this directed cycle.
  NotAcyclic(cycle: List(Int))
}

/// Distance from the source to `target`, if reachable.
pub fn distance(paths: Paths, target: Int) -> Result(Int, Nil) {
  dict.get(paths.dist, target)
}

/// The node sequence `[source, ..., target]` of a shortest path.
pub fn path(paths: Paths, target: Int) -> Result(List(Int), Nil) {
  use _ <- result.try(dict.get(paths.dist, target))
  Ok(unwind(paths.pred, paths.source, target, []))
}

fn unwind(pred: Dict(Int, Int), source: Int, node: Int, acc: List(Int)) {
  case node == source {
    True -> [node, ..acc]
    False -> {
      let assert Ok(p) = dict.get(pred, node)
      unwind(pred, source, p, [node, ..acc])
    }
  }
}

/// Dijkstra's algorithm with a pairing heap and lazy deletion:
/// O((V + E) log V). Fails if any edge has a negative weight.
pub fn dijkstra(g: Graph, source: Int) -> Result(Paths, PathError) {
  use _ <- result.try(check_source(g, source))
  use _ <- result.try(check_non_negative(g))
  let frontier = heap.new() |> heap.insert(0, source)
  Ok(settle(
    g,
    frontier,
    Paths(source, dict.from_list([#(source, 0)]), dict.new()),
    dict.new(),
  ))
}

fn settle(
  g: Graph,
  frontier: heap.Heap(Int),
  paths: Paths,
  done: Dict(Int, Bool),
) -> Paths {
  case heap.pop(frontier) {
    Error(Nil) -> paths
    Ok(#(d, node, rest)) ->
      case dict.has_key(done, node) {
        True -> settle(g, rest, paths, done)
        False -> {
          let #(frontier, paths) =
            list.fold(graph.neighbors(g, node), #(rest, paths), fn(state, n) {
              let #(frontier, paths) = state
              let #(next, w) = n
              let candidate = d + w
              case dict.get(paths.dist, next) {
                Ok(old) if old <= candidate -> state
                _ -> #(
                  heap.insert(frontier, candidate, next),
                  Paths(
                    ..paths,
                    dist: dict.insert(paths.dist, next, candidate),
                    pred: dict.insert(paths.pred, next, node),
                  ),
                )
              }
            })
          settle(g, frontier, paths, dict.insert(done, node, True))
        }
      }
  }
}

/// Shortest `#(distance, path)` from `source` to `target` with Dijkstra.
pub fn shortest_path(
  g: Graph,
  source: Int,
  target: Int,
) -> Result(Result(#(Int, List(Int)), Nil), PathError) {
  use paths <- result.try(dijkstra(g, source))
  Ok({
    use d <- result.try(distance(paths, target))
    use p <- result.try(path(paths, target))
    Ok(#(d, p))
  })
}

fn check_source(g: Graph, source: Int) -> Result(Nil, PathError) {
  case graph.has_node(g, source) {
    True -> Ok(Nil)
    False -> Error(UnknownNode(source))
  }
}

fn check_non_negative(g: Graph) -> Result(Nil, PathError) {
  case list.find(graph.edges(g), fn(e) { e.weight < 0 }) {
    Ok(e) -> Error(NegativeEdge(e.from, e.to, e.weight))
    Error(Nil) -> Ok(Nil)
  }
}

/// Bellman-Ford: handles negative weights in O(VE). If a negative cycle is
/// reachable from the source, returns `NegativeCycle` with a witness cycle
/// `[v0, ..., vk]` (edges `v0 -> v1 -> ... -> vk -> v0`, smallest id first).
/// In an undirected graph a negative edge is itself a negative cycle.
pub fn bellman_ford(g: Graph, source: Int) -> Result(Paths, PathError) {
  use _ <- result.try(check_source(g, source))
  let start = Paths(source, dict.from_list([#(source, 0)]), dict.new())
  bf_rounds(graph.arcs(g), graph.node_count(g), 1, start)
}

fn bf_rounds(
  arcs: List(graph.Edge),
  n: Int,
  round: Int,
  paths: Paths,
) -> Result(Paths, PathError) {
  let #(paths, last) = relax_all(arcs, paths)
  case last {
    None -> Ok(paths)
    Some(x) ->
      case round >= n {
        True -> Error(NegativeCycle(extract_cycle(paths.pred, x, n)))
        False -> bf_rounds(arcs, n, round + 1, paths)
      }
  }
}

fn relax_all(arcs: List(graph.Edge), paths: Paths) -> #(Paths, Option(Int)) {
  list.fold(arcs, #(paths, None), fn(state, e) {
    let #(paths, _) = state
    case dict.get(paths.dist, e.from) {
      Error(Nil) -> state
      Ok(du) ->
        case dict.get(paths.dist, e.to) {
          Ok(dv) if dv <= du + e.weight -> state
          _ -> #(
            Paths(
              ..paths,
              dist: dict.insert(paths.dist, e.to, du + e.weight),
              pred: dict.insert(paths.pred, e.to, e.from),
            ),
            Some(e.to),
          )
        }
    }
  })
}

// A node relaxed in round n has a predecessor chain that, after n steps,
// is guaranteed to be inside a negative cycle.
fn extract_cycle(pred: Dict(Int, Int), x: Int, n: Int) -> List(Int) {
  let on_cycle = step_back(pred, x, n)
  let assert Ok(p) = dict.get(pred, on_cycle)
  collect_cycle(pred, on_cycle, p, [on_cycle]) |> rotate_to_min
}

fn step_back(pred: Dict(Int, Int), node: Int, steps: Int) -> Int {
  case steps {
    0 -> node
    _ -> {
      let assert Ok(p) = dict.get(pred, node)
      step_back(pred, p, steps - 1)
    }
  }
}

fn collect_cycle(
  pred: Dict(Int, Int),
  start: Int,
  node: Int,
  acc: List(Int),
) -> List(Int) {
  case node == start {
    True -> acc
    False -> {
      let assert Ok(p) = dict.get(pred, node)
      collect_cycle(pred, start, p, [node, ..acc])
    }
  }
}

fn rotate_to_min(cycle: List(Int)) -> List(Int) {
  let assert Ok(smallest) = list.reduce(cycle, int.min)
  let #(before, after) = list.split_while(cycle, fn(n) { n != smallest })
  list.append(after, before)
}

/// Single-source shortest paths in a directed acyclic graph in O(V + E),
/// relaxing edges in topological order. Negative weights are fine.
pub fn dag_paths(g: Graph, source: Int) -> Result(Paths, PathError) {
  use _ <- result.try(check_source(g, source))
  use order <- result.try(
    traverse.topological_sort(g) |> result.map_error(NotAcyclic),
  )
  let start = Paths(source, dict.from_list([#(source, 0)]), dict.new())
  Ok(
    list.fold(order, start, fn(paths, node) {
      case dict.get(paths.dist, node) {
        Error(Nil) -> paths
        Ok(du) ->
          list.fold(graph.neighbors(g, node), paths, fn(paths, n) {
            let #(next, w) = n
            case dict.get(paths.dist, next) {
              Ok(dv) if dv <= du + w -> paths
              _ ->
                Paths(
                  ..paths,
                  dist: dict.insert(paths.dist, next, du + w),
                  pred: dict.insert(paths.pred, next, node),
                )
            }
          })
      }
    }),
  )
}

/// All-pairs shortest distances with Floyd-Warshall in O(V^3). The result
/// maps `#(from, to)` to the distance for every pair with a path (including
/// `#(v, v) -> 0`). Fails with a witness if any negative cycle exists.
pub fn floyd_warshall(g: Graph) -> Result(Dict(#(Int, Int), Int), PathError) {
  let nodes = graph.nodes(g)
  let init =
    list.fold(
      graph.arcs(g),
      dict.from_list(list.map(nodes, fn(v) { #(#(v, v), 0) })),
      fn(d, e) { keep_min(d, #(e.from, e.to), e.weight) },
    )
  let dist =
    list.fold(nodes, init, fn(d, k) {
      let into_k =
        list.filter_map(nodes, fn(i) {
          dict.get(d, #(i, k)) |> result.map(fn(w) { #(i, w) })
        })
      let from_k =
        list.filter_map(nodes, fn(j) {
          dict.get(d, #(k, j)) |> result.map(fn(w) { #(j, w) })
        })
      list.fold(into_k, d, fn(d, ik) {
        list.fold(from_k, d, fn(d, kj) {
          keep_min(d, #(ik.0, kj.0), ik.1 + kj.1)
        })
      })
    })
  case
    list.find(nodes, fn(v) { result.unwrap(dict.get(dist, #(v, v)), 0) < 0 })
  {
    Error(Nil) -> Ok(dist)
    Ok(v) ->
      case bellman_ford(g, v) {
        Error(err) -> Error(err)
        Ok(_) -> panic as "unreachable: Floyd-Warshall and Bellman-Ford disagree"
      }
  }
}

fn keep_min(d: Dict(#(Int, Int), Int), key: #(Int, Int), w: Int) {
  case dict.get(d, key) {
    Ok(old) if old <= w -> d
    _ -> dict.insert(d, key, w)
  }
}

/// A* search from `source` to `target`. `heuristic(node)` must never
/// overestimate the remaining distance (admissible); nodes are re-expanded
/// when a shorter route is found, so inconsistent-but-admissible heuristics
/// still give optimal answers. With a consistent heuristic each node is
/// expanded at most once. Weights must be non-negative.
pub fn astar(
  g: Graph,
  source: Int,
  target: Int,
  heuristic: fn(Int) -> Int,
) -> Result(Result(#(Int, List(Int)), Nil), PathError) {
  use _ <- result.try(check_source(g, source))
  use _ <- result.try(check_non_negative(g))
  let start = Paths(source, dict.from_list([#(source, 0)]), dict.new())
  let open = heap.new() |> heap.insert(heuristic(source), #(source, 0))
  Ok(astar_loop(g, target, heuristic, open, start))
}

fn astar_loop(
  g: Graph,
  target: Int,
  h: fn(Int) -> Int,
  open: heap.Heap(#(Int, Int)),
  paths: Paths,
) -> Result(#(Int, List(Int)), Nil) {
  use #(_, #(node, cost), rest) <- result.try(heap.pop(open))
  case dict.get(paths.dist, node) {
    Ok(best) if best < cost -> astar_loop(g, target, h, rest, paths)
    _ ->
      case node == target {
        True -> path(paths, target) |> result.map(fn(p) { #(cost, p) })
        False -> {
          let #(open, paths) =
            list.fold(graph.neighbors(g, node), #(rest, paths), fn(state, n) {
              let #(open, paths) = state
              let #(next, w) = n
              let candidate = cost + w
              case dict.get(paths.dist, next) {
                Ok(old) if old <= candidate -> state
                _ -> #(
                  heap.insert(open, candidate + h(next), #(next, candidate)),
                  Paths(
                    ..paths,
                    dist: dict.insert(paths.dist, next, candidate),
                    pred: dict.insert(paths.pred, next, node),
                  ),
                )
              }
            })
          astar_loop(g, target, h, open, paths)
        }
      }
  }
}
