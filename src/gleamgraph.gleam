//// gleamgraph: graph algorithms in pure Gleam.
////
//// The library lives in the `gleamgraph/*` modules. Running the package
//// prints a small demonstration.

import gleam/int
import gleam/io
import gleam/list
import gleam/string
import gleamgraph/graph
import gleamgraph/shortest
import gleamgraph/traverse

pub fn main() -> Nil {
  let g =
    graph.from_edges(graph.Directed, [
      #(1, 2, 7),
      #(1, 3, 9),
      #(1, 6, 14),
      #(2, 3, 10),
      #(2, 4, 15),
      #(3, 4, 11),
      #(3, 6, 2),
      #(4, 5, 6),
      #(6, 5, 9),
    ])
  io.println("bfs from 1:  " <> show(traverse.bfs(g, 1)))
  io.println("dfs from 1:  " <> show(traverse.dfs(g, 1)))
  case traverse.topological_sort(g) {
    Ok(order) -> io.println("topological: " <> show(order))
    Error(cycle) -> io.println("cycle:       " <> show(cycle))
  }
  case shortest.shortest_path(g, 1, 5) {
    Ok(Ok(#(d, path))) ->
      io.println(
        "1 -> 5:      " <> show(path) <> " (" <> int.to_string(d) <> ")",
      )
    _ -> io.println("1 -> 5:      unreachable")
  }
}

fn show(nodes: List(Int)) -> String {
  nodes |> list.map(int.to_string) |> string.join(" ")
}
