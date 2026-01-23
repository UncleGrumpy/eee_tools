%% unit tests for nvs_csv module
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

-module(nvs_csv_tests).
-include_lib("eunit/include/eunit.hrl").

-ifdef(TEST).
-compile(export_all).
-endif.

nvs_csv_read_entries_test() ->
    CsvContent = "key,type,encoding,value\nfoo,data,binary,21\nbar,data,binary,AtomVM NVS Test\n",
    Unique = integer_to_list(erlang:unique_integer([positive])),
    Filename = filename:absname("test_nvs_" ++ Unique ++ ".csv"),
    {Entry1, Entry2} =
        try
            ok = file:write_file(Filename, CsvContent, [write, raw]),
            {ok, Entries} = nvs_csv:read_file(Filename),
            [E1, E2 | _T] = Entries,
            {E1, E2}
        after
            file:delete(Filename)
        end,
    ?assertEqual(foo, maps:get(key, Entry1)),
    ?assertEqual(data, maps:get(type, Entry1)),
    ?assertEqual(binary, maps:get(encoding, Entry1)),
    ?assertEqual(<<"21">>, maps:get(value, Entry1)),
    ?assertEqual(bar, maps:get(key, Entry2)),
    ?assertEqual(data, maps:get(type, Entry2)),
    ?assertEqual(binary, maps:get(encoding, Entry2)),
    ?assertEqual(<<"AtomVM NVS Test">>, maps:get(value, Entry2)).
