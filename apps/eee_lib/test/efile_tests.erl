%% unit tests for efile module
%% This is part of eee_tools
%%
%% Copyright (c) 2025 Winford (Uncle Grumpy) <winford@object.stream>
%% All rights reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%%
%% SPDX-FileCopyrightText: 2025 Winford (Uncle Grumpy) <winford@object.stream>
%% SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later

-module(efile_tests).
-include_lib("eunit/include/eunit.hrl").

-ifdef(TEST).
-compile(export_all).
-endif.

efile_write_read_string_test() ->
    Path = get_path(),
    TestData = <<"# eee_tools test\nsuccess!\n">>,
    try
        [
            ?assertEqual(ok, efile:write(Path, TestData, binary)),
            ?assertEqual({ok, TestData}, efile:read(Path))
        ]
    after
        cleanup(Path)
    end.

parse_atomvm_modes_test() ->
    [
        ?assertEqual({[o_wronly], 8#644}, efile:parse_atomvm_modes([write])),
        ?assertMatch({[o_rdonly], _}, efile:parse_atomvm_modes([read])),
        ?assertEqual({[o_rdwr], 8#644}, efile:parse_atomvm_modes([read, write])),
        ?assertEqual(
            {[o_wronly, o_append, o_sync], 8#644}, efile:parse_atomvm_modes([sync, append, write])
        ),
        ?assertMatch({[o_excl, o_rdonly], _}, efile:parse_atomvm_modes([read, exclusive])),
        ?assertError(no_open_modes, efile:parse_atomvm_modes([8#644])),
        ?assertError(no_open_modes, efile:parse_atomvm_modes([]))
    ].

%% compatibility functions
get_path() ->
    case erlang:system_info(machine) of
        "BEAM" ->
            TmpDir = filename:basedir(user_cache, "eee_lib_test"),
            File = filename:join(TmpDir, "test.txt"),
            case filelib:ensure_dir(File) of
                ok -> ok;
                {error, Reason} -> error({no_parent_dir, Reason})
            end,
            File;
        "ATOM" ->
            "./test.txt"
    end.

cleanup(File) ->
    case erlang:system_info(machine) of
        "BEAM" ->
            file:delete(File);
        "ATOM" ->
            case string:find(File, " ") of
                nomatch ->
                    atomvm:subprocess("/usr/bin", ["rm", File], [], [stdout]);
                _ ->
                    error(io_lib:format("Test file and path cannot contain spaces! (~p)~n", [File]))
            end
    end.

%% AtomVM Entrypoint
start() ->
    efile_write_read_string_test(),
    parse_atomvm_modes_test().
