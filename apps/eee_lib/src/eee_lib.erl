%% esp_lib support functions for various eee_tools apps
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
%% @doc Library of utility functions for the eee_tools suite.
%%
%% Helper functions for spawning external applications via ports.
%% @end
%%-------------------------------------------------------------------
-module(eee_lib).

-export([
    parse_int_string/1,
    port_execute_log/3, port_execute_log/4,
    port_execute_simple/2, port_execute_simple/3,
    reverse_endian/1
]).

%%-------------------------------------------------------------------
%% @param Str String representing an integer
%% @returns {ok, integer()} | {error, Reason}
%% @doc Get an integer from a string representation
%%
%% The string may be a decimal number, for example "1048576", a hexadecimal string "0x100000", or
%% a human readable size in kilobytes or megabytes, such as "1024k", "1025KB", "1M", "1mb". Case
%% does not matter when processing strings.
%%
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-spec parse_int_string(Str :: string() | undefined) ->
    {ok, Int :: integer()} | {error, Reason :: term()}.
parse_int_string(Str) when is_list(Str) ->
    Str1 = string:lowercase(string:trim(Str)),
    try
        case string:prefix(Str1, "0x") of
            nomatch ->
                case check_suffix(Str1) of
                    {undefined, Val} ->
                        case string:to_integer(Val) of
                            {error, _} = IError -> IError;
                            {Int, _} -> {ok, Int}
                        end;
                    {"k", Val} ->
                        case string:to_integer(Val) of
                            {error, _} = KError -> KError;
                            {Int, _} -> {ok, Int * 1024}
                        end;
                    {"m", Val} ->
                        case string:to_integer(Val) of
                            {error, _} = MError -> MError;
                            {Int, _} -> {ok, Int * 1024 * 1024}
                        end;
                    Error0 ->
                        Error0
                end;
            _ ->
                HexNum = string:slice(Str1, 2),
                Result =
                    try
                        list_to_integer(HexNum, 16)
                    catch
                        _:_ ->
                            {error, malformed_hex_integer}
                    end,
                case Result of
                    {error, _} = Ret ->
                        Ret;
                    _ ->
                        {ok, Result}
                end
        end
    catch
        _:Error ->
            {error, Error}
    end;
parse_int_string(_) ->
    {error, no_integer}.

%%-------------------------------------------------------------------
%% @param Command name of the external command to be executed
%% @param Args list of arguments to be passed to the command
%% @returns ok
%% @doc Run an external command, ignoring logging or output.
%%
%% This function can be used to execute a command that produces no output, or the output is not
%% needed, only caring that that command exited successfully. The process will wait for up to 2
%% minutes to allow for long running operations, such as flashing a large image to an ESP32 device
%% at a low baud rate. An error will be raised if problems are encountered.
%%
%% @equiv port_execute_simple(CmdName, Args, 120000)
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-spec port_execute_simple(CmdName :: string(), Args :: list()) -> ok.
port_execute_simple(CmdName, Args) ->
    port_execute_simple(CmdName, Args, 120000),
    ok.

%%-------------------------------------------------------------------
%% @param Command name of the external command to be executed
%% @param Args list of arguments to be passed to the command
%% @param Timeout maximum time (in milliseconds) to allow the external executable to return
%% @returns ok | {ok, iodata()}
%% @doc Run an external command, collecting stdout and stderr output.
%%
%% Spawns an external executable and waits for the specified timeout for completion. Any output
%% produced will be returned in an `ok' tuple, otherwise a bare `ok' is returned. Raises an error
%% if problems are encountered.
%%
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-spec port_execute_simple(CmdName :: string(), Args :: list(), Timeout :: non_neg_integer()) ->
    ok | {ok, Output :: iodata()}.
port_execute_simple(CmdName, Args, Timeout) ->
    Executable =
        case os:find_executable(CmdName) of
            false -> error({enoent, CmdName});
            Path -> Path
        end,
    CMD =
        try
            open_port({spawn_executable, Executable}, [
                {args, Args}, stderr_to_stdout, use_stdio, exit_status
            ])
        catch
            error:enoent ->
                error({enoent, CmdName});
            error:eacces ->
                error({eacces, Executable});
            C:E:Trace ->
                error({{CmdName, Args}, C, E, Trace})
        end,
    wait_for_exit(CMD, CmdName, Timeout, []).

%%-------------------------------------------------------------------
%% @param Command name of the external command to be executed
%% @param Args list of arguments to be passed to the command
%% @param Logfile path to log file, or `none'
%% @returns ok | {ok, iodata()}
%% @doc Run an external command, storing output to a file.
%%
%% Spawns an external executable and waits for up to 2 minutes for the executable to return,
%% logging any output produced by the external command to a file, or returning it in an `ok' tuple
%% if the `Logfile' parameter is 'none`. When logging to a file an `ok' will be returned, or an
%% error raised on failure.
%%
%% @equiv port_execute_log(Cmd, Args, LogFile, 120000)
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-spec port_execute_log(
    Cmd :: string(), Args :: [string()], LogFile :: file:name_all() | none | stdout
) -> Result :: ok | {ok, iodata()}.
port_execute_log(Cmd, Args, LogFile) ->
    port_execute_log(Cmd, Args, LogFile, 120000).

%%-------------------------------------------------------------------
%% @param Command name of the external command to be executed
%% @param Args list of arguments to be passed to the command
%% @param Logfile path to log file, or `none'
%% @param Timeout maximum time (in milliseconds) to allow the external executable to return
%% @returns ok | {ok, iodata()} or raises an error
%% @doc Run an external command, storing output to a file.
%%
%% Spawns an external executable and waits for up to 2 minutes for the executable to return,
%% logging any output produced by the external command to a file, or returning it in an `ok' tuple
%% if the `Logfile' parameter is 'none`. When logging to a file an `ok' will be returned, or an
%% error raised on failure.
%%
%% Caution should be used when using this function with a command that will produce a lot of log
%% output, the logged data is held in memory until the command exits and output written to disk, or
%% sent to the console.
%%
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-spec port_execute_log(
    Cmd :: string(), Args :: [string()], LogFile :: file:name_all(), Timeout :: non_neg_integer()
) -> Result :: ok | {ok, iodata()}.
port_execute_log(Cmd, Args, LogFile, Timeout) ->
    Executable =
        case os:find_executable(Cmd) of
            false -> error({enoent, Cmd});
            Path -> Path
        end,
    CmdName = filename:basename(Executable),
    case LogFile of
        none ->
            ok;
        _ ->
            {{Y, M, D}, {H, I, S}} = calendar:local_time(),
            LogBegin = io_lib:format("~s executed at ~p/~p/~p ~p:~p:~p~n", [
                CmdName, Y, M, D, H, I, S
            ]),
            case efile:write(LogFile, LogBegin, [append, {encoding, utf8}]) of
                ok -> ok;
                {error, Reason} -> error({open_log_for_write, Reason})
            end
    end,
    CmdPort =
        try
            open_port({spawn_executable, Executable}, [
                {args, Args}, stderr_to_stdout, use_stdio, exit_status
            ])
        catch
            error:enoent ->
                error({enoent, CmdName});
            error:eacces ->
                error({eacces, Executable});
            C:E:Trace ->
                error({Executable, Args, C, E, Trace})
        end,
    case LogFile of
        none ->
            wait_for_exit(CmdPort, CmdName, Timeout, []);
        _ ->
            log_command_output(CmdPort, CmdName, Timeout, LogFile)
    end.

%%-------------------------------------------------------------------
%% @param Binary the bytes to be reversed
%% @returns binary()
%% @doc Reverse the endianness of a binary
%%
%% A naive utility for reversing the bytes in a binary, can take a big-endian or little-endian and
%% will return the inverse.
%%
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-spec reverse_endian(Binary :: binary()) -> Reversed :: binary().
reverse_endian(Binary) when is_binary(Binary) ->
    Size = byte_size(Binary) * 8,
    <<X:Size/integer-little>> = Binary,
    <<X:Size/integer-big>>.

%%===================================================================
%% Internal Functions
%%===================================================================

-spec wait_for_exit(
    CmdPort :: port(), CmdName :: string(), Timeout :: non_neg_integer(), Output :: [string()]
) -> ok | {ok, Output :: string()}.
wait_for_exit(CmdPort, CmdName, Timeout, Output) ->
    receive
        {CmdPort, {data, Data}} ->
            wait_for_exit(CmdPort, CmdName, Timeout, [Data | Output]);
        {CmdPort, {exit_status, 0}} ->
            case lists:flatten(lists:reverse(Output)) of
                [] ->
                    ok;
                Output1 ->
                    {ok, string:trim(unicode:characters_to_list(Output1))}
            end;
        {CmdPort, {exit_status, Status}} ->
            error({CmdName, {exit_status, Status}})
    after Timeout ->
        port_close(CmdPort),
        error({timeout, {CmdName, Timeout}})
    end.

-spec log_command_output(
    CmdPort :: port(), CmdName :: string(), Timeout :: non_neg_integer(), LogFile :: file:name_all()
) -> ok.
log_command_output(CmdPort, CmdName, Timeout, LogFile) ->
    receive
        {CmdPort, {data, Data}} ->
            file:write_file(LogFile, Data, [append, {encoding, utf8}]),
            log_command_output(CmdPort, CmdName, Timeout, LogFile);
        {CmdPort, {exit_status, 0}} ->
            ok;
        {CmdPort, {exit_status, Status}} ->
            Msg = io_lib:format("Command ~s failed! Exit status ~p.~n", [CmdName, Status]),
            file:write_file(LogFile, Msg, [append, {encoding, utf8}]),
            error({CmdName, {exit_status, Status}, LogFile})
    after Timeout ->
        port_close(CmdPort),
        error({CmdName, {timeout, Timeout}})
    end.

-spec check_suffix(Str :: string()) ->
    {K_or_M :: string() | undefined, Num :: string()} | {error, Reason :: term()}.
check_suffix(Str) ->
    case string:take(Str, "mb,m,kb,k", false, trailing) of
        {Size, "k"} -> {"k", Size};
        {Size, "kb"} -> {"k", Size};
        {Size, "m"} -> {"m", Size};
        {Size, "mb"} -> {"m", Size};
        {Size, ""} -> {undefined, Size};
        {_, _} -> {error, {malformed_integer, Str}}
    end.
