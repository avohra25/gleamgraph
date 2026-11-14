//// Breadth-first and depth-first traversal, reachability and
//// topological ordering.

import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import gleam/set.{type Set}
import gleamgraph/graph.{type Graph}
import gleamgraph/heap

/// Nodes reachable from `start` in breadth-first order. Neighbours are
/// visited in insertion order. Unknown start nodes yield `[start]` only if
/// the node exists, otherwise `[]`.
pub fn bfs(g: Graph, start: Int) -> List(Int) {
  bfs_layers(g, start) |> list.flatten
}

/// BFS layers: `[[start], nodes at distance 1, nodes at distance 2, ...]`.
pub fn bfs_layers(g: Graph, start: Int) -> List(List(Int)) {
  case graph.has_node(g, start) {
    False -> []
    True -> layers(g, [start], set.from_list([start]), [])
  }
}

fn layers(
  g: Graph,
  frontier: List(Int),
  seen: Set(Int),
  acc: List(List(Int)),
) -> List(List(Int)) {
  case frontier {
    [] -> list.reverse(acc)
    _ -> {
      let #(next, seen) =
        list.fold(frontier, #([], seen), fn(state, node) {
          list.fold(graph.successors(g, node), state, fn(state, n) {
            let #(next, seen) = state
            case set.contains(seen, n) {
              True -> state
              False -> #([n, ..next], set.insert(seen, n))
            }
          })
        })
      layers(g, list.reverse(next), seen, [frontier, ..acc])
    }
  }
}

/// Hop counts (unweighted distances) from `start` to every reachable node.
pub fn hop_distances(g: Graph, start: Int) -> Dict(Int, Int) {
  bfs_layers(g, start)
  |> list.index_fold(dict.new(), fn(acc, layer, depth) {
    list.fold(layer, acc, fn(acc, node) { dict.insert(acc, node, depth) })
  })
}

/// Nodes reachable from `start` in depth-first preorder (the order a
/// recursive DFS visiting neighbours in insertion order would produce).
pub fn dfs(g: Graph, start: Int) -> List(Int) {
  case graph.has_node(g, start) {
    False -> []
    True -> dfs_loop(g, [start], set.new(), [])
  }
}

fn dfs_loop(
  g: Graph,
  stack: List(Int),
  seen: Set(Int),
  acc: List(Int),
) -> List(Int) {
  case stack {
    [] -> list.reverse(acc)
    [node, ..rest] ->
      case set.contains(seen, node) {
        True -> dfs_loop(g, rest, seen, acc)
        False -> {
          let unseen =
            graph.successors(g, node)
            |> list.filter(fn(n) { !set.contains(seen, n) })
          dfs_loop(g, list.append(unseen, rest), set.insert(seen, node), [
            node,
            ..acc
          ])
        }
      }
  }
}

/// The set of nodes reachable from `start` (including `start`).
pub fn reachable(g: Graph, start: Int) -> Set(Int) {
  dfs(g, start) |> set.from_list
}

/// Is there a path from `from` to `to`?
pub fn has_path(g: Graph, from: Int, to: Int) -> Bool {
  set.contains(reachable(g, from), to)
}

/// Topologically sort a directed graph with Kahn's algorithm. Among the
/// nodes that are ready at each step the smallest id is taken first, so the
/// result is the lexicographically smallest topological order.
///
/// On failure returns `Error(cycle)` where `cycle` is a list of nodes
/// `[v0, v1, ..., vk]` such that `v0 -> v1 -> ... -> vk -> v0`.
/// Undirected graphs with at least one edge always contain a cycle.
pub fn topological_sort(g: Graph) -> Result(List(Int), List(Int)) {
  let nodes = graph.nodes(g)
  let zero = dict.from_list(list.map(nodes, fn(n) { #(n, 0) }))
  let indegree =
    list.fold(graph.arcs(g), zero, fn(acc, e) {
      dict.upsert(acc, e.to, fn(d) { option.unwrap(d, 0) + 1 })
    })
  let ready =
    dict.fold(indegree, heap.new(), fn(h, node, d) {
      case d {
        0 -> heap.insert(h, node, node)
        _ -> h
      }
    })
  kahn(g, ready, indegree, [], 0, list.length(nodes))
}

fn kahn(
  g: Graph,
  ready: heap.Heap(Int),
  indegree: Dict(Int, Int),
  acc: List(Int),
  done: Int,
  total: Int,
) -> Result(List(Int), List(Int)) {
  case heap.pop(ready) {
    Error(Nil) ->
      case done == total {
        True -> Ok(list.reverse(acc))
        False -> Error(find_cycle(g, set.from_list(acc)))
      }
    Ok(#(_, node, rest)) -> {
      let #(ready, indegree) =
        list.fold(graph.successors(g, node), #(rest, indegree), fn(state, n) {
          let #(ready, indegree) = state
          let d = unwrap_result(dict.get(indegree, n)) - 1
          let indegree = dict.insert(indegree, n, d)
          case d {
            0 -> #(heap.insert(ready, n, n), indegree)
            _ -> #(ready, indegree)
          }
        })
      kahn(g, ready, indegree, [node, ..acc], done + 1, total)
    }
  }
}

fn unwrap_result(r: Result(Int, Nil)) -> Int {
  case r {
    Ok(x) -> x
    Error(Nil) -> 0
  }
}

// Every node left over by Kahn's algorithm has a predecessor that is also
// left over, so walking predecessors must eventually revisit a node.
fn find_cycle(g: Graph, sorted: Set(Int)) -> List(Int) {
  let preds =
    list.fold(graph.arcs(g), dict.new(), fn(acc, e) {
      case set.contains(sorted, e.from) {
        True -> acc
        False ->
          dict.upsert(acc, e.to, fn(existing) {
            case existing {
              Some(ps) -> [e.from, ..ps]
              None -> [e.from]
            }
          })
      }
    })
  let assert [start, ..] =
    graph.nodes(g) |> list.filter(fn(n) { !set.contains(sorted, n) })
  walk_back(preds, start, dict.new(), [])
}

fn walk_back(
  preds: Dict(Int, List(Int)),
  node: Int,
  position: Dict(Int, Int),
  path: List(Int),
) -> List(Int) {
  case dict.get(position, node) {
    Ok(_) -> {
      // `path` is newest-first: the backward walk node <- ... <- node.
      // Taking the walk up to the repeat and reversing gives a forward cycle.
      let #(loop, _) = list.split_while(path, fn(n) { n != node })
      [node, ..loop] |> rotate_to_min
    }
    Error(Nil) -> {
      let assert Ok([p, ..]) = dict.get(preds, node)
      walk_back(preds, p, dict.insert(position, node, dict.size(position)), [
        node,
        ..path
      ])
    }
  }
}

fn rotate_to_min(cycle: List(Int)) -> List(Int) {
  let assert Ok(smallest) =
    list.reduce(cycle, fn(a, b) {
      case a < b {
        True -> a
        False -> b
      }
    })
  let #(before, after) = list.split_while(cycle, fn(n) { n != smallest })
  list.append(after, before)
}

/// True if a directed graph has no cycles.
pub fn is_acyclic(g: Graph) -> Bool {
  case topological_sort(g) {
    Ok(_) -> True
    Error(_) -> False
  }
}
