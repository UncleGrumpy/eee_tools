%% unit tests for eee_lib module
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

-module(eee_lib_tests).
-include_lib("eunit/include/eunit.hrl").

-ifdef(TEST).
-compile(export_all).
-dialyzer({nowarn_function, parse_int_string_invalid_test/0}).
-endif.

parse_int_string_test() ->
    [
        ?assertEqual({ok, 1024}, eee_lib:parse_int_string("1k")),
        ?assertEqual({ok, 4096}, eee_lib:parse_int_string("4kb")),
        ?assertEqual({ok, 10240}, eee_lib:parse_int_string("10K")),
        ?assertEqual({ok, 1024}, eee_lib:parse_int_string("1KB")),
        ?assertEqual({ok, 1048576}, eee_lib:parse_int_string("1m")),
        ?assertEqual({ok, 1048576}, eee_lib:parse_int_string("1mb")),
        ?assertEqual({ok, 1048576}, eee_lib:parse_int_string("1M")),
        ?assertEqual({ok, 1048576}, eee_lib:parse_int_string("1MB")),
        ?assertEqual({ok, 4096}, eee_lib:parse_int_string("0x1000")),
        ?assertEqual({ok, 16}, eee_lib:parse_int_string("0x10")),
        ?assertEqual({ok, 1024}, eee_lib:parse_int_string("1024")),
        ?assertEqual({ok, 16}, eee_lib:parse_int_string("16"))
    ].

parse_int_string_errors_test() ->
    [
        ?assertEqual({error, no_integer}, eee_lib:parse_int_string("")),
        ?assertEqual({error, no_integer}, eee_lib:parse_int_string("eight")),
        ?assertEqual({error, malformed_hex_integer}, eee_lib:parse_int_string("0x one hundred")),
        ?assertEqual({error, no_integer}, eee_lib:parse_int_string("onek")),
        ?assertEqual({error, no_integer}, eee_lib:parse_int_string("BOMB")),
        ?assertEqual({error, no_integer}, eee_lib:parse_int_string("KB")),
        ?assertEqual({error, no_integer}, eee_lib:parse_int_string("SUM"))
    ].

parse_int_string_invalid_test() ->
    [
        ?assertEqual({error, no_integer}, eee_lib:parse_int_string(atom)),
        ?assertEqual({error, no_integer}, eee_lib:parse_int_string(<<>>)),
        ?assertEqual({error, no_integer}, eee_lib:parse_int_string(#{size => 4, mod => "kb"}))
    ].

reverse_endian_test() ->
    [
        ?assertEqual(
            <<0, 64, 0, 127, 0, 0, 0, 1>>, eee_lib:reverse_endian(<<1, 0, 0, 0, 127, 0, 64, 0>>)
        ),
        ?assertNotEqual(<<1, 0, 1, 0>>, eee_lib:reverse_endian(<<1, 0, 1, 0>>)),
        ?assertEqual(<<>>, eee_lib:reverse_endian(<<>>)),
        ?assertEqual(<<1>>, eee_lib:reverse_endian(<<1>>)),
        ?assertEqual(<<$r, $a, $d, $a, $r>>, eee_lib:reverse_endian(<<$r, $a, $d, $a, $r>>)),
        ?assertEqual(<<$o, $l, $l, $e, $h>>, eee_lib:reverse_endian(<<$h, $e, $l, $l, $o>>))
    ].
