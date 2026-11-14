-module(gleamgraph_ffi).
-export([arguments/0, read_file/1, halt/1]).

arguments() ->
    [unicode:characters_to_binary(A) || A <- init:get_plain_arguments()].

read_file(Path) ->
    case file:read_file(Path) of
        {ok, Bin} -> {ok, Bin};
        {error, Reason} -> {error, atom_to_binary(Reason)}
    end.

halt(Code) ->
    erlang:halt(Code).
