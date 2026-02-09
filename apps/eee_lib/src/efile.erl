%% esp_fs File read and write library compatible with AtomVM and OTP
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
%% File System utilities for AtomVM and BEAM compatibility.
%%
%%-------------------------------------------------------------------
-module(efile).
-compile([{nowarn_unused, atomvm, posix_open}]).

-export([read/1, read/2, write/3, open/2, close/1]).

-type machine_string() :: string().
%% Either "BEAM" or "ATOM"
-type file_path() :: file:name_all() | iodata().
-type device() :: file:io_device() | atomvm:posix_fd().
-type mode() :: file:mode() | permissions().
-type permissions() :: 8#0000..8#4777.

%% When used on AtomVM these are translated as below:
%% |---------------------------|
%% | OTP Mode    | atomvm:posix_open_flag/0 |
%% |-------------|-------------|
%% |   `read'    | `o_rdonly'  |
%% |   `write'   | `o_wronly'  |
%% | `read' and `write' | `o_rdwr' |
%% |  `append'   | `o_append'  |
%% | `exclusive' |  `o_excl'   |
%% |   `sync'    |  `o_sync'   |
%% | `t:permissions()' | used as permissions mode (default 8#644)|
%% | [atomvm:posix_open_flag/0](https://doc.atomvm.org/main/apidocs/erlang/eavmlib/atomvm.html#posix-open-flag) | Passed through. Use with caution this will crash on BEAM |
%% |    `**'     | _All other options ignored_ |
%% |---------------------------|

%%-------------------------------------------------------------------
%% @param Path file or device to be opened
%% @param Opts list of options to be used when opening
%% @doc Open a file or device.
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-spec open(Path :: file:name_all() | iodata(), Modes :: [mode()]) ->
    {ok, Fd :: file:io_device() | atomvm:posix_fd()} | {error, Reason :: term()}.
open(Path, Modes) ->
    File = filename:absname(Path),
    case erlang:system_info(machine) of
        "BEAM" ->
            file:open(File, Modes);
        "ATOM" ->
            {OpenFlags, FileMode} = parse_atomvm_modes(Modes, [], undefined),
            atomvm:posix_open(File, OpenFlags, FileMode)
    end.

%%-------------------------------------------------------------------
%% @param Fd device to be closed
%% @doc Close an `io_device'.
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-spec close(Fd :: file:io_device() | atomvm:posix_fd()) -> ok | {error, Reason :: term()}.
close(Fd) ->
    case erlang:system_info(machine) of
        "BEAM" ->
            file:close(Fd);
        "ATOM" ->
            atomvm:posix_close(Fd)
    end.

%%-------------------------------------------------------------------
%% @param FD the identifier of an open file to be read
%% @param Size number of bytes to read
%% @doc Read bytes from an open file.
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-spec read(FD :: device(), Size :: non_neg_integer()) ->
    {ok, FileData :: string() | binary()} | eof | {error, Reason :: any()}.
read(FD, Size) ->
    try
        case is_device(FD) of
            true -> ok;
            false -> error(ebadf)
        end,
        Result =
            case erlang:system_info(machine) of
                "BEAM" ->
                    file:read(FD, Size);
                "ATOM" ->
                    atomvm:posix_read(FD, Size);
                _ ->
                    {error, "Unsupported virtual machine!"}
            end,
        Result
    catch
        error:ebadf ->
            {error, ebadf}
    end.

%%-------------------------------------------------------------------
%% @param Path file to be read
%% @doc Read contents of a file.
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-spec read(Path :: file_path()) -> {ok, FileData :: binary()} | eof | {error, Reason :: any()}.
read(Path) ->
    read(Path, 4096, <<>>).

%%-------------------------------------------------------------------
%% @param Path path to file to be written
%% @param Content data to be written
%% @param Options text, binary, or mode()
%% @doc Write data to file or stdout.
%%
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-spec write(
    Path :: file_path() | stdout, Content :: binary() | string(), Modes :: binary | text | [mode()]
) ->
    ok | {error, Reason :: any()}.
write(stdout, Content, _Modes) ->
    io:put_chars(Content);
% write(standard_io, Content, [{encoding, latin1}, sync | Modes]);
write(Path, Content, Modes) ->
    Opts =
        case Modes of
            binary -> [write, binary, sync];
            text -> [write, {encoding, latin1}, sync];
            Opts0 when is_list(Opts0) -> Opts0
        end,
    write_file(erlang:system_info(machine), Path, Content, Opts).

%%===================================================================
%% Internal Functions
%%===================================================================

-spec is_device(Fd :: device()) -> boolean().
is_device(Fd) ->
    case erlang:system_info(machine) of
        "BEAM" ->
            case Fd of
                {file_descriptor, _, _} ->
                    true;
                Pid when is_pid(Pid) ->
                    true;
                Port when is_port(Port) ->
                    true;
                _ ->
                    false
            end;
        "ATOM" ->
            is_binary(Fd) orelse is_reference(Fd)
    end.

-spec read(Path :: file_path(), BufferSize :: non_neg_integer(), Acc :: binary()) ->
    {ok, FileData :: binary()} | {error, Reason :: any()}.
read(Path, BufferSize, Acc) ->
    case erlang:system_info(machine) of
        "BEAM" ->
            file:read_file(Path);
        "ATOM" ->
            case atomvm:posix_open(Path, [o_rdonly]) of
                {ok, Fd} ->
                    try atomvm_read(Fd, BufferSize, Acc) of
                        {ok, Data} -> {ok, Data};
                        Error -> Error
                    after
                        atomvm:posix_close(Fd)
                    end;
                {error, FileError} ->
                    {error, {fs_read, FileError}}
            end;
        Vm ->
            {error, "Unsupported virtual machine", Vm}
    end.

-spec atomvm_read(Fd :: atomvm:posix_fd(), BufferSize :: non_neg_integer(), Acc :: binary()) ->
    {ok, FileData :: binary()} | {error, Reason :: any()}.
atomvm_read(Fd, BufferSize, Acc) ->
    Offset = byte_size(Acc),
    case atomvm:posix_read(Fd, BufferSize) of
        {ok, Data} ->
            atomvm_read(Fd, BufferSize, <<Acc:Offset/binary, Data/binary>>);
        eof ->
            {ok, Acc};
        Error ->
            Error
    end.

-spec write_file(
    Machine :: machine_string(), Path :: file_path(), Content :: iodata(), Opts :: list()
) ->
    ok | {error, Reason :: any()}.
write_file("BEAM", Path, Content, Opts) ->
    file:write_file(Path, Content, Opts);
write_file("ATOM", Path, Content, Opts) when is_list(Content) ->
    write_file("ATOM", Path, list_to_binary(Content), Opts);
write_file("ATOM", Path, Content, Opts) ->
    {Opts0, Mode} = parse_atomvm_modes(Opts),
    case atomvm:posix_open(Path, Opts0, Mode) of
        {ok, Fd0} ->
            case atomvm:posix_write(Fd0, Content) of
                {ok, _Len} ->
                    atomvm:posix_close(Fd0);
                {error, Error} ->
                    atomvm:posix_close(Fd0),
                    {error, {file_write_error, Error}}
            end;
        {error, Reason} ->
            {error, {file_open_error, Reason}}
    end.

-spec parse_atomvm_modes(Modes :: [mode()]) ->
    {OpenFlags :: [atomvm:posix_open_flag()], FileMode :: permissions()}.
parse_atomvm_modes(Opts) ->
    parse_atomvm_modes(Opts, [], undefined).

-spec parse_atomvm_modes(
    Modes :: [mode()],
    OFlags :: [atomvm:posix_open_flag()] | [],
    FileMode :: undefined | permissions()
) ->
    {OpenFlags :: [atomvm:posix_open_flag()], FileMode :: permissions()}.
parse_atomvm_modes([], OpenFlags, FileMode) ->
    case {OpenFlags, FileMode} of
        {[], _} ->
            error(no_open_modes);
        {_, undefined} ->
            {OpenFlags, 8#644};
        {_, _} ->
            {OpenFlags, FileMode}
    end;
parse_atomvm_modes([read | Modes], OFlags, FileMode) ->
    case lists:member(o_wronly, OFlags) of
        true ->
            parse_atomvm_modes(Modes, [o_rdwr | lists:subtract(OFlags, [o_wronly])], FileMode);
        false ->
            parse_atomvm_modes(Modes, [o_rdonly | OFlags], FileMode)
    end;
parse_atomvm_modes([write | Modes], OFlags, FileMode) ->
    case lists:member(o_rdonly, OFlags) of
        true ->
            parse_atomvm_modes(Modes, [o_rdwr | lists:subtract(OFlags, [o_rdonly])], FileMode);
        false ->
            parse_atomvm_modes(Modes, [o_wronly | OFlags], FileMode)
    end;
parse_atomvm_modes([append | Modes], OFlags, FileMode) ->
    parse_atomvm_modes(Modes, [o_append | OFlags], FileMode);
parse_atomvm_modes([exclusive | Modes], OFlags, FileMode) ->
    parse_atomvm_modes(Modes, [o_excl | OFlags], FileMode);
parse_atomvm_modes([sync | Modes], OFlags, FileMode) ->
    parse_atomvm_modes(Modes, [o_sync | OFlags], FileMode);
parse_atomvm_modes([Mode0 | Modes], OFlags, _FileMode) when
    is_integer(Mode0) andalso Mode0 >= 0 andalso Mode0 =< 8#4777
->
    parse_atomvm_modes(Modes, OFlags, Mode0);
parse_atomvm_modes([Opt | Modes], OFlags, FileMode) when is_atom(Opt) ->
    case lists:prefix("o_", atom_to_list(Opt)) of
        true ->
            parse_atomvm_modes(Modes, [Opt | OFlags], FileMode);
        false ->
            parse_atomvm_modes(Modes, OFlags, FileMode)
    end;
parse_atomvm_modes([_Opt | Modes], OFlags, FileMode) ->
    parse_atomvm_modes(Modes, OFlags, FileMode).
