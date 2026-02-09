%% CLI entry for NVS partition generator.
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

%% References:
%% https://github.com/espressif/esp-idf-nvs-partition-gen/blob/main/esp_idf_nvs_partition_gen/nvs_partition_gen.py

%%-------------------------------------------------------------------
%% @doc
%% Command-line interface entry point for esp_nvs escript and common
%% type definitions.
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-module(nvs_cli).
-include("esp_nvs.hrl").
-include_lib("kernel/include/file.hrl").

-export([main/1]).

%% Needed so compiler doesn't optimize it away =(
-export([generate/1]).

-define(ESCRIPT_NAME, esp_nvs).

-record(config, {
    size = ?NVS_PARTITION_SIZE_DEFAULT :: pos_integer(),
    input_type :: file | device | undefined,
    input_path :: file:name_all(),
    verbosity = 1 :: 0..3,
    output_file :: file:name_all()
}).

-type config() :: #config{}.
-type command() :: generate.
-type args() :: [string()].

-spec main(Args :: args()) -> no_return().
main(Args) ->
    io:setopts([{encoding, latin1}]),
    %% Example Args: nvs_cli:main(["generate", "nvs_data.csv", "nvs.bin"])
    {Cmd, Config} = parse_cli_args(Args),
    try
        print_info("===> Executing task ~p...", [Cmd], Config),
        ok = ?MODULE:Cmd(Config)
    catch
        _:Error:S ->
            exit_error("*** Task ~p failed with reason: ~p~n~p", [Cmd, Error, S])
    end,
    halt(0).

%% @hidden
-spec generate(Config :: config()) -> ok.
generate(
    #config{size = Size, input_type = Type, input_path = File, output_file = Out} = Config
) when Type =:= file ->
    {ok, Entries} = nvs_csv:read_file(File),
    print_info("===> Read csv file...", [], Config),
    print_debug("===> Parsed entries: ~p", [Entries], Config),
    PackedEntries = nvs_entry:encode_maps(Entries),
    print_debug("===> Packed binary entries:\n\t~p", [PackedEntries], Config),
    InitialPage =
        case nvs_page:init(Size) of
            {ok, {readonly, {InitialPage1, _NumPages}}} ->
                print_notice(
                    "===> Warning! NVS size 0x~.16B is less than 0x3000, NVS will be read-only",
                    [Size],
                    Config
                ),
                InitialPage1;
            {ok, {InitialPage0, _NumPages0}} ->
                InitialPage0
        end,
    print_info("===> NVS page initialized...", [], Config),
    Pages = nvs_page:insert_entries(PackedEntries, InitialPage, []),
    print_info("===> Entries inserted into page record", [], Config),
    Bin = pages_to_bin(Pages, Config),
    print_info("===> Generating binary data complete...", [], Config),
    ok = efile:write(Out, Bin, binary),
    print_notice("===> Wrote NVS binary to ~s.\n", [Out], Config),
    ok;
generate(
    #config{output_file = _Out, input_path = _Device, size = _Size, input_type = device} = _Config
) ->
    %% TODO: add device input to csv out support
    exit_error("Reading NVS partitions from devices is not yet supported", []).

-spec pages_to_bin(Pages :: nvs_page:page() | [nvs_page:page()], Config :: config()) -> binary().
pages_to_bin(Pages, #config{size = Size} = _Config) ->
    try
        nvs_page:build_partition(Pages, Size)
    catch
        error:{partition_overflow, {BinLen, Size}} ->
            exit_error("NVS data (~p bytes) exceeds partition size (~p bytes)", [BinLen, Size])
    end.

-spec parse_cli_args(Args :: args()) -> {Cmd :: command(), #config{}}.
parse_cli_args(Args) ->
    ConfigInit = #{
        size => ?NVS_PARTITION_SIZE_DEFAULT,
        verbosity => 1
    },
    parse_cli_args(Args, {undefined, ConfigInit}).

-spec parse_cmd_args(Cmd :: command() | undefined, Cfg :: map()) ->
    {Command :: command(), Config :: #config{}}.
parse_cmd_args(undefined, _Cfg) ->
    exit_error("Missing command. See --help for usage.", []);
parse_cmd_args(Cmd, Cfg) ->
    Config =
        #config{
            size = maps:get(size, Cfg, ?NVS_PARTITION_SIZE_DEFAULT),
            input_type = maps:get(input_type, Cfg),
            verbosity = maps:get(verbosity, Cfg),
            input_path = maps:get(input, Cfg),
            output_file = maps:get(output_file, Cfg)
        },
    print_debug("===> Parsed config record:\n\t~s", [format_config_record(Config)], #config{
        verbosity = maps:get(verbosity, Cfg)
    }),
    {Cmd, Config}.

-spec parse_cli_args(Args :: args(), {Cmd :: command() | undefined, Cfg :: map()}) ->
    {Command :: command(), #config{}}.

parse_cli_args([], {undefined, _Cfg}) ->
    exit_error("Missing command. See --help for usage.", []);
parse_cli_args([], {Cmd, _Cfg}) ->
    exit_error("Missing INPUT and OUTPUT arguments for command ~p. See --help for usage.", [Cmd]);
parse_cli_args(["--help" | _], _) ->
    print_usage(),
    halt(0);
parse_cli_args(["-h" | _], _) ->
    print_usage(),
    halt(0);
parse_cli_args(["--quiet" | Rest], {Cmd, Cfg}) ->
    parse_cli_args(Rest, {Cmd, Cfg#{verbosity => 0}});
parse_cli_args(["-q" | Rest], {Cmd, Cfg}) ->
    parse_cli_args(Rest, {Cmd, Cfg#{verbosity => 0}});
parse_cli_args(["--verbose" | Rest], {Cmd, #{verbosity := Verbosity} = Cfg}) ->
    parse_cli_args(Rest, {Cmd, Cfg#{verbosity => maybe_more_verbose(Verbosity)}});
parse_cli_args(["-v" | Rest], {Cmd, #{verbosity := Verbosity} = Cfg}) ->
    parse_cli_args(Rest, {Cmd, Cfg#{verbosity => maybe_more_verbose(Verbosity)}});
parse_cli_args(["-vv" | Rest], {Cmd, #{verbosity := Verbosity} = Cfg}) ->
    parse_cli_args(Rest, {Cmd, Cfg#{verbosity => maybe_more_verbose(Verbosity, 2)}});
parse_cli_args(["-vvv" | Rest], {Cmd, #{verbosity := Verbosity} = Cfg}) ->
    parse_cli_args(Rest, {Cmd, Cfg#{verbosity => maybe_more_verbose(Verbosity, 3)}});
parse_cli_args(["--outdir", Dir | Rest], {Cmd, #{verbosity := Verbosity} = Cfg}) ->
    OutDir = filename:absname(Dir),
    print_debug("===> Using output dir: ~s", [OutDir], #config{verbosity = Verbosity}),
    parse_cli_args(Rest, {Cmd, Cfg#{outdir => OutDir}});
parse_cli_args([Cmd | Rest], {undefined, #{verbosity := Verbosity} = Cfg}) ->
    case Cmd of
        "generate" ->
            print_debug("===> Parsed command: ~s", [Cmd], #config{verbosity = Verbosity}),
            parse_cli_args(Rest, {generate, Cfg});
        _ ->
            exit_error("No valid command", [])
    end;
parse_cli_args([In, Out | Size], {Cmd, #{verbosity := Verbosity} = Cfg}) when
    not is_number(In) andalso not is_number(Out)
->
    Input = filename:absname(In),
    Type = get_input_type(Input),
    print_debug("===> Input ~s is type ~p", [Input, Type], #config{verbosity = Verbosity}),
    Output = filename:absname(Out),
    Filename = filename:basename(Output),
    Dir = maps:get(outdir, Cfg, filename:dirname(Output)),
    case filelib:is_dir(Dir) of
        true ->
            ok;
        false ->
            exit_error("The directory path to output file ~p must exist", [Output])
    end,
    OutFile = filename:absname(filename:join(Dir, Filename)),
    if
        Output =:= OutFile ->
            ok;
        true ->
            print_info("===> Using override path to generate output ~s", [OutFile], #config{
                verbosity = Verbosity
            })
    end,
    print_debug("===> Output will be written to file ~s", [OutFile], #config{verbosity = Verbosity}),
    case Size of
        [] ->
            print_info("===> Using default size 0x~.16B", [maps:get(size, Cfg)], #config{
                verbosity = Verbosity
            }),
            parse_cmd_args(Cmd, Cfg#{input_type => Type, input => Input, output_file => OutFile});
        [Size0 | []] ->
            Size1 =
                case eee_lib:parse_int_string(Size0) of
                    {ok, Size2} ->
                        Size2;
                    {error, no_integer} ->
                        exit_error("The given size (~p) does not represent an integer", [Size0])
                end,
            print_debug("===> Decoded size ~s to ~p", [Size0, Size1], #config{verbosity = Verbosity}),
            parse_cmd_args(Cmd, Cfg#{
                input_type => Type, input => Input, output_file => OutFile, size => Size1
            });
        [_Size0 | More] ->
            exit_error("Unrecognized option ~p", [More])
    end;
parse_cli_args([_Input | []], {Cmd, _Cfg}) ->
    exit_error("Missing OUTPUT argument for command ~p. See --help for usage.", [Cmd]);
parse_cli_args([Unknown | _], _Cfg) ->
    exit_error("Unknown option ~p", [Unknown]).

-spec maybe_more_verbose(Num :: non_neg_integer()) -> non_neg_integer().
maybe_more_verbose(0) ->
    0;
maybe_more_verbose(Num) when Num =< 2 ->
    NewVerbosity = Num + 1,
    print_notice(
        "===> ~p: ~s mode enabled", [?ESCRIPT_NAME, get_verbosity(NewVerbosity)], #config{
            verbosity = NewVerbosity
        }
    ),
    NewVerbosity;
maybe_more_verbose(_Num) ->
    print_notice("===> Notice: 'verbose' used more than twice options as no effect", [], #config{
        verbosity = 3
    }),
    3.

-spec maybe_more_verbose(Num :: non_neg_integer(), Increase :: pos_integer()) -> non_neg_integer().
maybe_more_verbose(0, _) ->
    0;
maybe_more_verbose(Num, Increase) when Num =< 2 ->
    NewVerbosity = Num + Increase,
    case NewVerbosity of
        NewVerbosity when NewVerbosity > 3 ->
            print_notice("===> Notice: 'verbose' used more than twice has no effect", [], #config{
                verbosity = 3
            }),
            3;
        _ ->
            print_info(
                "===> ~p: ~s mode enabled", [?ESCRIPT_NAME, get_verbosity(NewVerbosity)], #config{
                    verbosity = NewVerbosity
                }
            ),
            NewVerbosity
    end;
maybe_more_verbose(_Num, _) ->
    print_notice("===> Notice: 'verbose' used more than twice options has no effect", [], #config{
        verbosity = 3
    }),
    3.

-spec get_verbosity(Num :: non_neg_integer()) -> quiet | notice | info | debug.
get_verbosity(Num) ->
    case Num of
        0 -> quiet;
        1 -> notice;
        2 -> info;
        Num when Num >= 3 -> debug
    end.

-spec get_input_type(Path :: file:name_all() | file:io_device()) -> file | device.
get_input_type(Path) ->
    case file:read_file_info(Path) of
        {ok, #file_info{type = device}} ->
            device;
        {ok, #file_info{type = regular}} ->
            file;
        {ok, _} ->
            exit_error("~p is not a supported input file or device path", [Path]);
        {error, Reason} ->
            exit_error("Failed to read ~p for reason: ~p", [Path, Reason])
    end.

-spec format_config_record(Config :: #config{}) -> string().
format_config_record(#config{
    size = Size, input_type = Type, input_path = Input, verbosity = Verbosity, output_file = Out
}) ->
    lists:flatten(
        io_lib:format(
            "#config{\n\t\tsize = ~p,\n\t\tinput_type = ~p,\n\t\tinput_path = ~p,\n\t\tverbosity = ~p,\n\t\toutput_path = ~p\n\t}",
            [Size, Type, Input, Verbosity, Out]
        )
    ).

-ifdef(TEST).
exit_error(Fmt, Args) ->
    Reason = io_lib:format("*** " ++ Fmt ++ "\n", Args),
    error({test_failed, Reason}).
-else.
exit_error(Fmt, Args) ->
    io:format(standard_error, "*** " ++ Fmt ++ "\n", Args),
    halt(1).
-endif.

print_notice(Fmt, Args, #config{verbosity = Log}) when Log >= 1 ->
    io:format(Fmt ++ "\n", Args);
print_notice(_Fmt, _Args, _Cfg) ->
    ok.

print_info(Fmt, Args, #config{verbosity = Log}) when Log >= 2 ->
    io:format(Fmt ++ "\n", Args);
print_info(_Fmt, _Args, _Cfg) ->
    ok.

print_debug(Fmt, Args, #config{verbosity = Log}) when Log >= 3 ->
    io:format(Fmt ++ "\n", Args);
print_debug(_Fmt, _Args, _Cfg) ->
    ok.

format_usage() ->
    lists:flatten([
        io_lib:format(
            "\n  Usage: ~w [-q, --quiet] [-v, --verbose] COMMAND [CMD_OPTS] INPUT OUTPUT [SIZE] (default 0x6000)\n",
            [?ESCRIPT_NAME]
        ),
        io_lib:format("\tparameters in [] are optional.\n\n", []),
        io_lib:format("  INPUT is a csv file.\n\n", []),
        io_lib:format(
            "  OUTPUT may be a filename, relative or absolute path for the output. If it is a bare filename it will be\n",
            []
        ),
        io_lib:format(
            "\twritten to the current working directory or inside --outdir, if supplied.\n\n",
            []
        ),
        io_lib:format(
            "  *SIZE option must be a multiple of 4096 bytes, if none is given the default 0x~.16B will be used, this is\n",
            [?NVS_PARTITION_SIZE_DEFAULT]
        ),
        io_lib:format(
            "\tthe size used for AtomVM release images and default builds. The minimum partition size is 0x3000 or\n",
            []
        ),
        io_lib:format(
            "\t12kB (12288 bytes) for read-write support. Partitions of size 0x1000 (4kB) or 0x2000 (8kB) are\n",
            []
        ),
        io_lib:format("\tsupported, but they will be read-only at runtime.\n\n", []),
        io_lib:format("  Commands:\n", []),
        io_lib:format(
            "\tgenerate:  Generate a Non-Volatile Storage binary partition from a csv file.\n\n", []
        ),
        io_lib:format("\t\tCommand Options:\n", []),
        io_lib:format(
            "\t\t--outdir:\tOverrides any leading path in the output file parameter, using this path\n",
            []
        ),
        io_lib:format(
            "\t\t\t\twith the output file basename. (Optional for ESP-IDF nvs_partition_gen.py\n\t\t\t\tcompatibility)\n\n",
            []
        ),
        io_lib:format("  Options:\n", []),
        io_lib:format(
            "\t-v, --verbose:\tIncrease verbosity (may be repeated for debug output)\n", []
        ),
        io_lib:format("\t-q, --quiet:\tSuppress all non error messages (overrides verbose\n", []),
        io_lib:format("\t\t\toption if present)\n", []),
        io_lib:format("  Examples:\n", []),
        io_lib:format("\t~w -q generate nvs_data.csv output.bin\n", [?ESCRIPT_NAME]),
        io_lib:format("\t~w generate nvs_data.csv output.bin 0x4000\n\n", [?ESCRIPT_NAME])
    ]).

print_usage() ->
    io:format("~s", [format_usage()]).
