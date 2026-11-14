//// Bipartite graphs: two-colouring and maximum matching.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/set.{type Set}
import gleamgraph/graph.{type Graph}

/// Split the nodes into two sides so that every edge crosses between them
/// (direction ignored). Each connected component's smallest node goes on
/// the left. Returns `Error(Nil)` if the graph has an odd cycle (including
/// a self-loop).
pub fn bipartition(g: Graph) -> Result(#(List(Int), List(Int)), Nil) {
  let u = case graph.is_directed(g) {
    True -> graph.to_undirected(g)
    False -> g
  }
  let colour =
    list.try_fold(graph.nodes(u), dict.new(), fn(colour, v) {
      case dict.has_key(colour, v) {
        True -> Ok(colour)
        False -> paint(u, [v], dict.insert(colour, v, True))
      }
    })
  case colour {
    Error(Nil) -> Error(Nil)
    Ok(colour) -> {
      let #(left, right) =
        list.partition(graph.nodes(u), fn(v) { dict.get(colour, v) == Ok(True) })
      Ok(#(left, right))
    }
  }
}

fn paint(
  g: Graph,
  stack: List(Int),
  colour: Dict(Int, Bool),
) -> Result(Dict(Int, Bool), Nil) {
  case stack {
    [] -> Ok(colour)
    [v, ..rest] -> {
      let assert Ok(c) = dict.get(colour, v)
      let step =
        list.try_fold(graph.successors(g, v), #(rest, colour), fn(state, w) {
          let #(stack, colour) = state
          case dict.get(colour, w) {
            Ok(cw) if cw == c -> Error(Nil)
            Ok(_) -> Ok(state)
            Error(Nil) -> Ok(#([w, ..stack], dict.insert(colour, w, !c)))
          }
        })
      case step {
        Error(Nil) -> Error(Nil)
        Ok(#(stack, colour)) -> paint(g, stack, colour)
      }
    }
  }
}

pub fn is_bipartite(g: Graph) -> Bool {
  bipartition(g) != Error(Nil)
}

/// Maximum matching between `left` nodes and their neighbours using
/// augmenting paths (Kuhn's algorithm), O(V E). Only edges leaving a left
/// node are used, so in a directed graph orient edges left to right.
/// Returns `#(left, right)` pairs sorted by left node.
pub fn bipartite_matching(g: Graph, left: List(Int)) -> List(#(Int, Int)) {
  let owner =
    list.fold(left, dict.new(), fn(owner, u) {
      let #(_, _, owner) = try_augment(g, u, set.new(), owner)
      owner
    })
  dict.to_list(owner)
  |> list.map(fn(p) { #(p.1, p.0) })
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
}

// `owner` maps a right node to the left node it is matched with.
fn try_augment(
  g: Graph,
  u: Int,
  visited: Set(Int),
  owner: Dict(Int, Int),
) -> #(Bool, Set(Int), Dict(Int, Int)) {
  list.fold_until(
    graph.successors(g, u),
    #(False, visited, owner),
    fn(state, r) {
      let #(_, visited, owner) = state
      case set.contains(visited, r) {
        True -> list.Continue(state)
        False -> {
          let visited = set.insert(visited, r)
          case dict.get(owner, r) {
            Error(Nil) -> list.Stop(#(True, visited, dict.insert(owner, r, u)))
            Ok(other) ->
              case try_augment(g, other, visited, owner) {
                #(True, visited, owner) ->
                  list.Stop(#(True, visited, dict.insert(owner, r, u)))
                #(False, visited, owner) ->
                  list.Continue(#(False, visited, owner))
              }
          }
        }
      }
    },
  )
}

/// Maximum matching of a bipartite graph, choosing the sides with
/// `bipartition`. Fails if the graph is not bipartite.
pub fn maximum_matching(g: Graph) -> Result(List(#(Int, Int)), Nil) {
  case bipartition(g) {
    Error(Nil) -> Error(Nil)
    Ok(#(left, _)) -> {
      let u = case graph.is_directed(g) {
        True -> graph.to_undirected(g)
        False -> g
      }
      Ok(bipartite_matching(u, left))
    }
  }
}
