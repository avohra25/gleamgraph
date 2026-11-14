//// Minimum spanning forests. Edge direction is ignored.

import gleam/int
import gleam/list
import gleam/order
import gleam/set.{type Set}
import gleamgraph/disjoint
import gleamgraph/graph.{type Edge, type Graph, Edge}
import gleamgraph/heap

/// A spanning forest: one spanning tree per connected component.
pub type Forest {
  Forest(weight: Int, edges: List(Edge))
}

/// Kruskal's algorithm: sort edges by weight, keep those joining two
/// different trees. O(E log E). Ties are broken by insertion order.
pub fn kruskal(g: Graph) -> Forest {
  let sorted =
    graph.edges(g)
    |> list.index_map(fn(e, i) { #(e, i) })
    |> list.sort(fn(a, b) {
      case int.compare({ a.0 }.weight, { b.0 }.weight) {
        order.Eq -> int.compare(a.1, b.1)
        other -> other
      }
    })
  let #(kept, _) =
    list.fold(sorted, #([], disjoint.from_list(graph.nodes(g))), fn(state, p) {
      let #(kept, ds) = state
      let e = p.0
      case disjoint.union(ds, e.from, e.to) {
        #(True, ds) -> #([e, ..kept], ds)
        #(False, ds) -> #(kept, ds)
      }
    })
  forest(list.reverse(kept))
}

/// Prim's algorithm with a pairing heap, restarted in every component.
/// O(E log V).
pub fn prim(g: Graph) -> Forest {
  let u = case graph.is_directed(g) {
    True -> graph.to_undirected(g)
    False -> g
  }
  let #(edges, _) =
    list.fold(graph.nodes(u), #([], set.new()), fn(state, root) {
      let #(edges, seen) = state
      case set.contains(seen, root) {
        True -> state
        False ->
          grow(u, push_all(u, root, heap.new()), set.insert(seen, root), edges)
      }
    })
  forest(list.reverse(edges))
}

fn push_all(g: Graph, node: Int, frontier: heap.Heap(Edge)) -> heap.Heap(Edge) {
  list.fold(graph.neighbors(g, node), frontier, fn(h, n) {
    heap.insert(h, n.1, Edge(node, n.0, n.1))
  })
}

fn grow(
  g: Graph,
  frontier: heap.Heap(Edge),
  seen: Set(Int),
  edges: List(Edge),
) -> #(List(Edge), Set(Int)) {
  case heap.pop(frontier) {
    Error(Nil) -> #(edges, seen)
    Ok(#(_, e, rest)) ->
      case set.contains(seen, e.to) {
        True -> grow(g, rest, seen, edges)
        False ->
          grow(g, push_all(g, e.to, rest), set.insert(seen, e.to), [e, ..edges])
      }
  }
}

fn forest(edges: List(Edge)) -> Forest {
  Forest(list.fold(edges, 0, fn(acc, e) { acc + e.weight }), edges)
}

/// Is `edges` a spanning forest of `g`: acyclic, and connecting exactly the
/// node pairs that `g` connects?
pub fn is_spanning_forest(g: Graph, edges: List(Edge)) -> Bool {
  let nodes = graph.nodes(g)
  let #(acyclic, ds) =
    list.fold(edges, #(True, disjoint.from_list(nodes)), fn(state, e) {
      let #(ok, ds) = state
      let #(merged, ds) = disjoint.union(ds, e.from, e.to)
      #(ok && merged, ds)
    })
  let g_components =
    graph.edges(g)
    |> list.fold(disjoint.from_list(nodes), fn(d, e) {
      disjoint.union(d, e.from, e.to).1
    })
    |> disjoint.count
  acyclic
  && disjoint.size(ds) == list.length(nodes)
  && disjoint.count(ds) == g_components
}
