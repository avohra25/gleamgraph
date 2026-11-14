//// Single-source shortest paths.

import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleamgraph/graph.{type Graph}
import gleamgraph/heap

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
