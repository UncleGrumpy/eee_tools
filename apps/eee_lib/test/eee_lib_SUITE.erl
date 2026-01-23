%% eee_lib_SUITE
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

-module(eee_lib_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-ifdef(TEST).
-compile(export_all).
-endif.

-define(TEST_FILE_PATH, "test.txt").
-define(TEST_FILE_STRING, "eee_tools test string").

all() ->
    [
        ecrc_crc32_le,
        ecrc_eee_crc32_le,
        efile_write,
        efile_read,
        eee_lib_port_execute_simple,
        run_eunits
    ].

init_per_suite(Config) -> Config.
end_per_suite(_Config) -> ok.
init_per_testcase(efile_write, Config) ->
    File = filename:join(?config(priv_dir, Config), ?TEST_FILE_PATH),
    [{file, File}, {data, ?TEST_FILE_STRING} | Config];
init_per_testcase(efile_read, Config) ->
    File = filename:join(?config(priv_dir, Config), ?TEST_FILE_PATH),
    ok = efile:write(File, ?TEST_FILE_STRING, text),
    [{file, File}, {data, ?TEST_FILE_STRING} | Config];
init_per_testcase(_TestCase, Config) ->
    Config.
end_per_testcase(_TestCase, _Config) -> ok.

run_eunits(_Config) ->
    [
        ?assertEqual(ok, eunit:test({ecrc_tests, crc32_le_test})),
        ?assertEqual(ok, eunit:test({ecrc_tests, eee_crc32_le_test})),
        ?assertEqual(ok, eunit:test({efile_tests, efile_write_read_string_test})),
        ?assertEqual(ok, eunit:test({efile_tests, parse_atomvm_modes_test})),
        ?assertEqual(ok, eunit:test({eee_lib_tests, parse_int_string_test})),
        ?assertEqual(ok, eunit:test({eee_lib_tests, parse_int_string_errors_test})),
        ?assertEqual(ok, eunit:test({eee_lib_tests, parse_int_string_invalid_test})),
        ?assertEqual(ok, eunit:test({eee_lib_tests, reverse_endian_test}))
    ].

ecrc_crc32_le(_Config) ->
    Crc32 = ecrc:crc32_le(<<16#32, 16#31>>),
    ECrc32 = ecrc:crc32_le(
        <<16#41, 16#74, 16#6f, 16#6d, 16#56, 16#4d, 16#20, 16#4e, 16#56, 16#53, 16#20, 16#54, 16#65,
            16#73, 16#74>>
    ),
    [
        ?assertEqual(binary:decode_unsigned(<<16#b4, 16#ab, 16#51, 16#43>>, little), Crc32),
        ?assertEqual(binary:decode_unsigned(<<16#4c, 16#4f, 16#3c, 16#f7>>, little), ECrc32)
    ].

ecrc_eee_crc32_le(_Config) ->
    Crc32 = ecrc:eee_crc32_le(<<16#32, 16#31>>, 16#00000000),
    ECrc32 = ecrc:eee_crc32_le(
        <<16#41, 16#74, 16#6f, 16#6d, 16#56, 16#4d, 16#20, 16#4e, 16#56, 16#53, 16#20, 16#54, 16#65,
            16#73, 16#74>>,
        16#00000000
    ),
    [
        ?assertEqual(binary:decode_unsigned(<<16#b4, 16#ab, 16#51, 16#43>>, little), Crc32),
        ?assertEqual(binary:decode_unsigned(<<16#4c, 16#4f, 16#3c, 16#f7>>, little), ECrc32)
    ].

efile_write(Config) ->
    File = proplists:get_value(file, Config),
    Data = proplists:get_value(data, Config),
    ?assertEqual(ok, efile:write(File, Data, text)).

efile_read(Config) ->
    File = proplists:get_value(file, Config),
    Data = proplists:get_value(data, Config),
    BinString = list_to_binary(Data),
    ?assertEqual({ok, BinString}, efile:read(File)),
    file:delete(File).

eee_lib_port_execute_simple(_Config) ->
    {{Y, M, D}, {_, _, _}} = erlang:universaltime(),
    Expect = lists:flatten(io_lib:format("~p-~p-~p", [Y, M, D])),
    {ok, Date} = eee_lib:port_execute_simple("date", ["-u", "+%Y-%-m-%-d"], 5000),
    [
        ?assertEqual(ok, eee_lib:port_execute_simple("true", [])),
        %% Beware possible race condition if test is run at exactly midnight UTC!
        ?assertEqual(Expect, Date)
    ].
