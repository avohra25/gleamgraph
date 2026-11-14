import gleam/string
import gleamgraph
import gleamgraph/graph
import gleamgraph/parse

const roads =
  "# comment line
undirected
1 2 7
1 3 9
1 6 14
2 3 10
2 4 15
3 4 11
3 6 2
4 5 6
5 6 9   # trailing comment
"

fn reader(path: String) -> Result(String, String) {
  case path {
    "roads.txt" -> Ok(roads)
    "neg.txt" -> Ok("0 1 2\n1 2 -3\n0 2 1\n")
    "loop.txt" -> Ok("0 1 1\n1 2 -2\n2 0 -2\n")
    "dag.txt" -> Ok("3 1\n1 2\n3 2\n")
    "bad.txt" -> Ok("1 2\n1 x\n")
    _ -> Error("enoent")
  }
}

pub fn parse_format_round_trip_test() {
  let assert Ok(g) = parse.parse(roads)
  assert graph.kind(g) == graph.Undirected
  assert graph.edge_count(g) == 9
  let with_isolated = graph.add_node(g, 42)
  let assert Ok(again) = parse.parse(parse.format(with_isolated))
  assert graph.edges(again) == graph.edges(with_isolated)
  assert graph.nodes(again) == graph.nodes(with_isolated)
  assert parse.parse("1 2 3 4")
    == Error(parse.ParseError(1, "expected `from to [weight]`"))
}

pub fn cli_path_test() {
  assert gleamgraph.run(["path", "roads.txt", "1", "5"], reader)
    == Ok("distance 20\n1 3 6 5\n")
  // Negative weights switch to Bellman-Ford.
  assert gleamgraph.run(["path", "neg.txt", "0", "2"], reader)
    == Ok("distance -1\n0 1 2\n")
  assert gleamgraph.run(["distances", "loop.txt", "0"], reader)
    == Error("negative cycle: 0 -> 1 -> 2 -> 0")
}

pub fn cli_misc_commands_test() {
  assert gleamgraph.run(["topo", "dag.txt"], reader) == Ok("3 1 2\n")
  assert gleamgraph.run(["bfs", "roads.txt", "1"], reader)
    == Ok("1 2 3 6 4 5\n")
  assert gleamgraph.run(["mst", "roads.txt"], reader)
    == Ok("weight 33\n3 6 2\n4 5 6\n1 2 7\n1 3 9\n5 6 9\n")
  let assert Ok(info) = gleamgraph.run(["info", "roads.txt"], reader)
  assert string.contains(info, "nodes       6")
}

pub fn cli_errors_test() {
  assert gleamgraph.run([], reader) == Ok(gleamgraph.usage)
  assert gleamgraph.run(["bfs", "missing.txt", "1"], reader)
    == Error("missing.txt: enoent")
  assert gleamgraph.run(["bfs", "bad.txt", "1"], reader)
    == Error("bad.txt: line 2: expected integers, got `1 x`")
  assert gleamgraph.run(["bfs", "roads.txt", "99"], reader)
    == Error("node 99 is not in the graph")
  let assert Error(message) =
    gleamgraph.run(["frobnicate", "roads.txt"], reader)
  assert string.starts_with(message, "unknown command")
}
