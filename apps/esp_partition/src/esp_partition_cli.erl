%% Escript for working with esp32 partitions
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
%% SPDX-FileCopyrightText: 2025 Winford (Uncle Grumpy) <winford@object.stream>
%% SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later

%%-------------------------------------------------------------------
%% @doc
%% ESP32 partition table generation tool - Command-line interface
%%
%% This module handles command-line argument parsing and file I/O.
%% The core library functionality is provided by esp_partition.
%%
%%-------------------------------------------------------------------
-module(esp_partition_cli).
-include("esp_partition.hrl").
-define(ESCRIPT_NAME, esp_partition).

-export([main/1]).

-type options() :: [string()].
%%-------------------------------------------------------------------
%% CLI Options: [
%%     "--help" | "-h"
%%     "--verify"
%%     "--no-verify"
%%     "--disable-md5sum"
%%     "--quiet" | "-q"
%%     "--offset" | "-o", Offset :: `non_neg_integer()'
%%     "--flash-size" | "-s", Size :: "1mb" | "2mb" | "4mb" | "8mb" | "16mb" | "32mb" | "64mb" | "128mb"
%%  ]
%% Defaults:
%%      --verify --offset 0x8000 --flash-size 4mb
%%-------------------------------------------------------------------

-define(TABLE_OFFSET, 16#8000).
-define(DEFAULT_FLASH_SIZE, 16#400000).

%%===================================================================
%% API Functions
%%===================================================================

%% @doc Main entry point for the escript
-spec main(Args :: options()) -> none().
main(Args) ->
    io:setopts([{encoding, latin1}]),
    try parse_cli_args(Args) of
        {ok, InputFile, OutputFile, Config} ->
            ok = generate_binary_table(InputFile, OutputFile, Config),
            halt(0);
        {error, Message} ->
            print_error(format_error(Message)),
            halt(1)
    catch
        _:Error ->
            print_error(format_error(Error)),
            print_usage(),
            halt(1)
    end.

%%===================================================================
%% Internal Functions
%%===================================================================

-spec parse_cli_args(Args :: iolist()) ->
    {ok, Input :: file:name_all(), Output :: file:name_all(), Config :: #partmap_config{}}
    | {error, Reason :: term()}.
parse_cli_args(Args) ->
    parse_cli_args(Args, #{
        input => undefined,
        output => stdout,
        quiet => false,
        md5sum => true,
        secure => none,
        table_offset => ?TABLE_OFFSET,
        verify => true,
        force_verify => false,
        flash_size => ?DEFAULT_FLASH_SIZE
    }).

parse_cli_args([], Acc) ->
    Input = maps:get(input, Acc),
    case Input of
        undefined ->
            {error, no_input};
        _ ->
            Verify =
                case maps:get(force_verify, Acc, false) of
                    true ->
                        true;
                    false ->
                        maps:get(verify, Acc, true)
                end,
            Config = #partmap_config{
                quiet = maps:get(quiet, Acc),
                md5sum = maps:get(md5sum, Acc),
                secure = maps:get(secure, Acc),
                table_offset = maps:get(table_offset, Acc),
                verify = Verify,
                flash_size = maps:get(flash_size, Acc)
            },
            {ok, Input, maps:get(output, Acc), Config}
    end;
parse_cli_args(["--help" | _Rest], _Acc) ->
    print_usage(),
    halt(0);
parse_cli_args(["-h" | _Rest], _Acc) ->
    print_usage(),
    halt(0);
parse_cli_args(["--quiet" | Rest], Acc) ->
    parse_cli_args(Rest, Acc#{quiet => true});
parse_cli_args(["-q" | Rest], Acc) ->
    parse_cli_args(Rest, Acc#{quiet => true});
parse_cli_args(["--disable-md5sum" | Rest], Acc) ->
    parse_cli_args(Rest, Acc#{md5sum => false});
parse_cli_args(["--no-verify" | Rest], Acc) ->
    parse_cli_args(Rest, Acc#{verify => false});
parse_cli_args(["--verify" | Rest], Acc) ->
    % verify is default
    parse_cli_args(Rest, Acc#{verify => true, force_verify => true});
parse_cli_args(["--offset", Value | Rest], Acc) ->
    case eee_lib:parse_int_string(Value) of
        {ok, Offset} -> parse_cli_args(Rest, Acc#{table_offset => Offset});
        {error, Reason} -> {error, io_lib:format("Invalid offset ~s, ~p", [Value, Reason])}
    end;
parse_cli_args(["-o", Value | Rest], Acc) ->
    case eee_lib:parse_int_string(Value) of
        {ok, Offset} -> parse_cli_args(Rest, Acc#{table_offset => Offset});
        {error, Reason} -> {error, io_lib:format("Invalid offset ~s, ~p", [Value, Reason])}
    end;
parse_cli_args(["--flash-size", Value | Rest], Acc) ->
    case eee_lib:parse_int_string(Value) of
        {ok, Size} ->
            parse_cli_args(Rest, Acc#{flash_size => Size});
        {error, Reason} ->
            {error, io_lib:format("Invalid flash size ~s, ~p", [Value, Reason])}
    end;
parse_cli_args(["-s", Value | Rest], Acc) ->
    case eee_lib:parse_int_string(Value) of
        {ok, Size} ->
            parse_cli_args(Rest, Acc#{flash_size => Size});
        {error, Reason} ->
            {error, io_lib:format("Invalid flash size ~s, ~p", [Value, Reason])}
    end;
%% TODO: Add support for Secure Boot
% parse_cli_args(["--secure" | Rest], Acc) ->
%     case Rest of
%         [Value | Rest2] when Value =/= [] andalso hd(Value) =/= $- ->
%             Secure =
%                 try list_to_existing_atom(Value)
%                 catch _:_ ->
%                     list_to_atom(Value)
%                 end,
%             parse_cli_args(Rest2, Acc#{secure => Secure});
%         _ ->
%             parse_cli_args(Rest, Acc#{secure => v1})
%     end;
%% TODO: Implement support for custom subtypes
%% input example: "--extra-partition-subtypes Type,Code;Type,Code"
% parse_cli_args(["--extra-partition-subtypes", Defs | Rest], Acc) ->
parse_cli_args([Arg | Rest], Acc) ->
    case Arg of
        [$- | _] ->
            {error, io_lib:format("Unknown option: ~s", [Arg])};
        _ ->
            case maps:get(input, Acc) of
                undefined ->
                    parse_cli_args(Rest, Acc#{input => Arg});
                _ ->
                    case maps:get(output, Acc) of
                        stdout ->
                            case list_to_binary(Arg) of
                                %% look for shell redirects
                                <<"|">> ->
                                    parse_cli_args([], Acc);
                                <<">">> ->
                                    parse_cli_args([], Acc);
                                <<">", _/binary>> ->
                                    parse_cli_args([], Acc);
                                <<"1>">> ->
                                    parse_cli_args([], Acc);
                                <<"1>", _/binary>> ->
                                    parse_cli_args([], Acc);
                                <<"2>">> ->
                                    parse_cli_args([], Acc);
                                <<"2>", _/binary>> ->
                                    parse_cli_args([], Acc);
                                %% not a redirect, use output filename
                                _ ->
                                    parse_cli_args(Rest, Acc#{output => Arg})
                            end;
                        _ ->
                            {error, "Too many positional parameters"}
                    end
            end
    end.

generate_binary_table(InputFile, OutputFile, Config) ->
    try
        case esp_partition_csv:table_from_csv_file(InputFile, Config) of
            {ok, Partitions} ->
                File = filename:basename(InputFile),
                print_status(io_lib:format("Processed input file ~s", [File]), Config),
                case Config#partmap_config.verify of
                    true ->
                        print_status("Verifying table data...", Config),
                        try esp_partition:verify_table(Partitions, Config) of
                            ok ->
                                print_status("Verification complete", Config)
                        catch
                            _:Error ->
                                print_error("Verification failed!"),
                                print_error(format_error(Error)),
                                halt(1)
                        end;
                    false ->
                        ok
                end,
                case Partitions of
                    [] ->
                        print_error("No partition data found!"),
                        halt(1);
                    _ ->
                        ok
                end,
                ok = write_output(InputFile, OutputFile, Partitions, Config),
                print_status(
                    io_lib:format("Success! Partition table written to ~s", [OutputFile]),
                    Config
                ),
                ok
        end
    catch
        _:Reason ->
            print_error(format_error(Reason)),
            halt(1)
    end.

% generate_csv_table(InputFile, OutputFile, Config) ->
%     case InputFile of
%         ["/dev/tty" | _] ->
%             Dump =
%               try eee_lib:port_execute_simple(),

write_output(InputFile, OutputFile, Partitions, Config) ->
    IsBinary = esp_partition:is_partition_or_table(InputFile),
    case IsBinary of
        {true, partition} ->
            try
                case esp_partition_csv:encode_csv_table(Partitions) of
                    {ok, Csv} ->
                        case efile:write(OutputFile, Csv, text) of
                            ok ->
                                ok;
                            {error, Reason} ->
                                print_error(
                                    io_lib:format("Cannot write file ~s: ~p", [OutputFile, Reason])
                                ),
                                halt(1)
                        end
                end
            catch
                error:Reason0:Trace ->
                    print_error(
                        io_lib:format("Unable to decode csv file ~s: ~p~n~w", [
                            InputFile, Reason0, Trace
                        ])
                    ),
                    halt(1)
            end;
        _ ->
            case Config#partmap_config.md5sum of
                true -> print_status("Generating md5sum...", Config);
                false -> ok
            end,
            try esp_partition:table_to_binary(Partitions, Config) of
                {ok, Binary} ->
                    case OutputFile of
                        stdout ->
                            case file:write(standard_io, Binary) of
                                ok ->
                                    ok;
                                {error, WriteError} ->
                                    error({output_failure, WriteError})
                            end;
                        _ ->
                            case efile:write(OutputFile, Binary, binary) of
                                ok ->
                                    print_status(
                                        io_lib:format("Output written to: ~s", [OutputFile]), Config
                                    );
                                {error, Reason} ->
                                    print_error(
                                        io_lib:format("Cannot write file ~s: ~p", [
                                            OutputFile, Reason
                                        ])
                                    ),
                                    halt(1)
                            end
                    end
            catch
                _:Error ->
                    print_error(format_error(Error)),
                    halt(1)
            end
    end.

format_error(no_partitions) ->
    "No partitions found in input file";
format_error({file_error, Path, Reason}) ->
    io_lib:format("File error reading ~s: ~p", [Path, Reason]);
format_error({parse_error, Type, Value}) ->
    io_lib:format("Parse error (~p): ~s", [Type, Value]);
format_error({encode_error, Type, Value}) ->
    io_lib:format("Encode error (~p): ~s", [Type, Value]);
format_error({validation_error, Name, Message}) ->
    io_lib:format("Partition ~s invalid: ~s", [Name, Message]);
format_error({duplicate_partition_names, Names}) ->
    io_lib:format("Duplicate partition names: ~p", [Names]);
format_error({partition_overlap, Name, Offset, LastEnd}) ->
    io_lib:format(
        "Partition ~s at offset 0x~.16B overlaps previous partition ending at 0x~.16B",
        [Name, Offset, LastEnd]
    );
format_error({partition_offset_below_table, Name, Offset, TableEnd}) ->
    io_lib:format(
        "Partition ~s offset 0x~.16B is below partition table end at 0x~.16B",
        [Name, Offset, TableEnd]
    );
format_error({partition_overlap, Name1, Offset1, Name2, Offset2, EndOffset2}) ->
    io_lib:format(
        "Partition ~s at 0x~.16B overlaps ~s at 0x~.16B-0x~.16B",
        [Name1, Offset1, Name2, Offset2, EndOffset2]
    );
format_error({multiple_otadata_partitions}) ->
    "Found multiple otadata partitions. Only one partition can be defined with type=\"data\"(1) and subtype=\"ota\"(0).";
format_error({invalid_otadata_size, Name, Size}) ->
    io_lib:format("otadata partition ~s has invalid size 0x~.16B, must be 0x2000", [Name, Size]);
format_error({md5_mismatch, Computed, Parsed}) ->
    io_lib:format("MD5 checksums don't match! (computed: 0x~s, parsed: 0x~s)", [Computed, Parsed]);
format_error({invalid_magic, Magic}) ->
    io_lib:format("Invalid magic bytes (~p) for partition definition", [Magic]);
format_error({input_error, Message}) ->
    io_lib:format("Input error: ~s", [Message]);
format_error({flash_overflow, {Size, Max}}) ->
    Mb = 1024 * 1024,
    io_lib:format("Partition table occupies ~.1fMB which does not fit in ~.1fMB flash", [
        Max / Mb, Size / Mb
    ]);
format_error(no_input) ->
    io_lib:format("Input file is required! See --help~n", []);
format_error(Error) ->
    io_lib:format("Unable to perform command, problem encountered: ~p", [Error]).

print_status(Message, #partmap_config{quiet = Quiet}) ->
    case Quiet of
        false -> io:format(standard_error, "~s~n", [Message]);
        true -> ok
    end.

print_error(Message) ->
    io:format(standard_error, "Error: ~s~n", [Message]).

print_usage() ->
    io:format("~n\tUsage:\n\t\t$ ~s [options] input [output] [shell redirects]~n~n", [?ESCRIPT_NAME]),
    io:format("\tOptions:~n"),
    io:format("\t --help, -h \t\t Print this help message~n", []),
    io:format("\t --quiet, -q \t\t Don't print non-critical messages~n", []),
    io:format(
        "\t --offset, -o <OFFSET> \t Set partition table offset, default 0x~.16B~n",
        [?TABLE_OFFSET]
    ),
    io:format("\t --disable-md5sum \t\t Disable md5 checksum~n", []),
    io:format("\t --no-verify \t\t Don't verify partition table~n", []),
    io:format(
        "\t --verify \t\t Verify partition table integrity (Enabled by default, this option will override --no-verify if both are present)~n",
        []
    ),
    io:format(
        "\t --flash-size, -s <SIZE> \t Abort if table partitions exceed flash size\n"
        "\t\t\t\t (Default: 4MB; Supported sizes: 1MB,2MB,4MB,8MB,16MB,32MB,64MB,128MB)~n",
        []
    ),
    io:format(
        "~n\tNote: If shell redirects are used to pipe output or redirect stderr to a file, the redirects must be the last arguments.\n"
        "\tAll status messages go to stderr so that stdout may be piped to another application, this may be useful for inspecting binaries~n"
        "\tor generating checksums.~n~n",
        []
    ).
