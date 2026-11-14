//// Connectivity: connected and strongly connected components, the
//// condensation DAG, bridges and articulation points.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/set.{type Set}
import gleamgraph/disjoint
import gleamgraph/graph.{type Graph}

/// Connected components, ignoring edge direction (so for a directed graph
/// these are the weakly connected components). Each component is sorted and
/// components are ordered by their smallest node.
pub fn connected_components(g: Graph) -> List(List(Int)) {
  graph.edges(g)
  |> list.fold(disjoint.from_list(graph.nodes(g)), fn(ds, e) {
    disjoint.union(ds, e.from, e.to).1
  })
  |> disjoint.groups
}

/// Number of connected components (ignoring direction).
pub fn component_count(g: Graph) -> Int {
  list.length(connected_components(g))
}

/// True if every node can reach every other ignoring direction. The empty
/// graph counts as connected.
pub fn is_connected(g: Graph) -> Bool {
  component_count(g) <= 1
}

type Tarjan {
  Tarjan(
    index: Dict(Int, Int),
    low: Dict(Int, Int),
    stack: List(Int),
    on_stack: Set(Int),
    counter: Int,
    found: List(List(Int)),
  )
}

/// Strongly connected components with Tarjan's algorithm in O(V + E).
/// Each component is sorted and components are ordered by smallest node.
/// For an undirected graph these coincide with the connected components.
pub fn strongly_connected_components(g: Graph) -> List(List(Int)) {
  let start = Tarjan(dict.new(), dict.new(), [], set.new(), 0, [])
  let state =
    list.fold(graph.nodes(g), start, fn(state, v) {
      case dict.has_key(state.index, v) {
        True -> state
        False -> strong_connect(g, v, state)
      }
    })
  state.found
  |> list.map(list.sort(_, int.compare))
  |> list.sort(fn(a, b) { int.compare(head(a), head(b)) })
}

fn strong_connect(g: Graph, v: Int, state: Tarjan) -> Tarjan {
  let state =
    Tarjan(
      ..state,
      index: dict.insert(state.index, v, state.counter),
      low: dict.insert(state.low, v, state.counter),
      stack: [v, ..state.stack],
      on_stack: set.insert(state.on_stack, v),
      counter: state.counter + 1,
    )
  let state =
    list.fold(graph.successors(g, v), state, fn(state, w) {
      case dict.get(state.index, w) {
        Error(Nil) -> {
          let state = strong_connect(g, w, state)
          lower(state, v, get(state.low, w))
        }
        Ok(w_index) ->
          case set.contains(state.on_stack, w) {
            True -> lower(state, v, w_index)
            False -> state
          }
      }
    })
  case get(state.low, v) == get(state.index, v) {
    False -> state
    True -> {
      let #(component, rest) = pop_until(state.stack, v, [])
      Tarjan(
        ..state,
        stack: rest,
        on_stack: list.fold(component, state.on_stack, set.delete),
        found: [component, ..state.found],
      )
    }
  }
}

fn lower(state: Tarjan, v: Int, value: Int) -> Tarjan {
  case value < get(state.low, v) {
    True -> Tarjan(..state, low: dict.insert(state.low, v, value))
    False -> state
  }
}

fn pop_until(
  stack: List(Int),
  v: Int,
  acc: List(Int),
) -> #(List(Int), List(Int)) {
  case stack {
    [] -> #(acc, [])
    [top, ..rest] ->
      case top == v {
        True -> #([top, ..acc], rest)
        False -> pop_until(rest, v, [top, ..acc])
      }
  }
}

/// Collapse every strongly connected component to one node. Returns the
/// condensation DAG (node `i` is the `i`-th component of
/// `strongly_connected_components`, edges deduplicated with weight 1) and a
/// map from original node to component index.
pub fn condensation(g: Graph) -> #(Graph, Dict(Int, Int)) {
  let components = strongly_connected_components(g)
  let owner =
    components
    |> list.index_fold(dict.new(), fn(acc, comp, i) {
      list.fold(comp, acc, fn(acc, v) { dict.insert(acc, v, i) })
    })
  let pairs =
    graph.arcs(g)
    |> list.filter_map(fn(e) {
      let a = get(owner, e.from)
      let b = get(owner, e.to)
      case a == b {
        True -> Error(Nil)
        False -> Ok(#(a, b))
      }
    })
    |> list.unique
  let dag =
    graph.directed()
    |> graph.add_nodes(list.index_map(components, fn(_, i) { i }))
  #(list.fold(pairs, dag, fn(d, p) { graph.add_edge(d, p.0, p.1, 1) }), owner)
}

type Lowlink {
  Lowlink(
    disc: Dict(Int, Int),
    low: Dict(Int, Int),
    timer: Int,
    bridges: List(#(Int, Int)),
    cut: Set(Int),
  )
}

/// Bridges: edges whose removal disconnects their endpoints. Direction is
/// ignored. Parallel edges are never bridges. Each bridge is reported as
/// `#(a, b)` with `a < b`, sorted.
pub fn bridges(g: Graph) -> List(#(Int, Int)) {
  lowlink(g).bridges |> list.sort(compare_pairs)
}

/// Articulation points (cut vertices): nodes whose removal increases the
/// number of connected components. Direction is ignored. Sorted.
pub fn articulation_points(g: Graph) -> List(Int) {
  lowlink(g).cut |> set.to_list |> list.sort(int.compare)
}

/// Is the graph 2-edge-connected (connected with no bridges)?
pub fn is_two_edge_connected(g: Graph) -> Bool {
  is_connected(g) && bridges(g) == []
}

/// Is the graph biconnected (connected, at least 2 nodes, no cut vertex)?
/// By this convention a single edge (2 nodes) is biconnected.
pub fn is_biconnected(g: Graph) -> Bool {
  graph.node_count(g) >= 2 && is_connected(g) && articulation_points(g) == []
}

fn lowlink(g: Graph) -> Lowlink {
  let u = case graph.is_directed(g) {
    True -> graph.to_undirected(g)
    False -> g
  }
  let start = Lowlink(dict.new(), dict.new(), 0, [], set.new())
  list.fold(graph.nodes(u), start, fn(state, v) {
    case dict.has_key(state.disc, v) {
      True -> state
      False -> visit(u, v, None, state)
    }
  })
}

fn visit(g: Graph, u: Int, parent: Option(Int), state: Lowlink) -> Lowlink {
  let state =
    Lowlink(
      ..state,
      disc: dict.insert(state.disc, u, state.timer),
      low: dict.insert(state.low, u, state.timer),
      timer: state.timer + 1,
    )
  let #(state, children, _) =
    list.fold(graph.successors(g, u), #(state, 0, False), fn(acc, v) {
      let #(state, children, skipped) = acc
      case parent == Some(v) && !skipped {
        // Skip the tree edge back to the parent exactly once, so a parallel
        // edge to the parent still counts as a back edge.
        True -> #(state, children, True)
        False ->
          case dict.get(state.disc, v) {
            Ok(dv) -> #(set_low(state, u, dv), children, skipped)
            Error(Nil) -> {
              let state = visit(g, v, Some(u), state)
              let low_v = get(state.low, v)
              let disc_u = get(state.disc, u)
              let state = set_low(state, u, low_v)
              let state = case low_v > disc_u {
                True ->
                  Lowlink(..state, bridges: [
                    #(int.min(u, v), int.max(u, v)),
                    ..state.bridges
                  ])
                False -> state
              }
              let state = case parent != None && low_v >= disc_u {
                True -> Lowlink(..state, cut: set.insert(state.cut, u))
                False -> state
              }
              #(state, children + 1, skipped)
            }
          }
      }
    })
  case parent == None && children > 1 {
    True -> Lowlink(..state, cut: set.insert(state.cut, u))
    False -> state
  }
}

fn set_low(state: Lowlink, u: Int, value: Int) -> Lowlink {
  case value < get(state.low, u) {
    True -> Lowlink(..state, low: dict.insert(state.low, u, value))
    False -> state
  }
}

fn get(d: Dict(Int, Int), k: Int) -> Int {
  let assert Ok(v) = dict.get(d, k)
  v
}

fn head(xs: List(Int)) -> Int {
  case xs {
    [x, ..] -> x
    [] -> 0
  }
}

fn compare_pairs(a: #(Int, Int), b: #(Int, Int)) {
  case int.compare(a.0, b.0) {
    order.Eq -> int.compare(a.1, b.1)
    other -> other
  }
}
