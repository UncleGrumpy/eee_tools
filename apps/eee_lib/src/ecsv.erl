%% ecsv CSV file parser
%% This is part of eee_tools
%%
%% Copyright (c) 2025 Winford (UncleGrumpy) <winford@object.stream>
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
%% @doc Library for generating and parsing CSV files.
%%
%% Designed for processing and generating CSV files compatible with ESP-IDF, but possibly useful
%% for other purposes. Only latin1 encoding is supported and only comas `,' are supported for
%% separating values.
%% @end
%%-------------------------------------------------------------------
-module(ecsv).

-export([decode_file/1, decode_file/2, decode_iolist/2]).

-export_type([key/0, value/0, mapped_type/0, column_head/0, column_header/0]).

-type mapped_csv() :: [map()].
%% A list of maps containing the column header keys, and their mapped value for each row.
-type mapped_type() :: string | binary | integer | atom.
%% The data type for the decoded `Value' mapped to the key
-type key() :: atom() | list() | undefined.
%% The key is an atom/0, `undefined' may be returned in the case that the row has more value
%% columns than header key columns. This would usually indicate a malformed csv file.
-type column_head() :: key() | {key(), mapped_type()}.
%% A header list may be key/0 names or mapped column_header/0, untyped keys default to `binary'.
-type column_header() :: list(column_head()).
%% A header list may be key/0 names or mapped column_header/0.
-type value() :: string() | binary() | integer() | atom() | undefined.
%% A decoded value or the atom `undefined'.
-type raw_value() :: string() | binary() | undefined.

%%-------------------------------------------------------------------
%% @param File CSV file to be decoded
%% @doc Decode a csv file
%%
%% Read a csv file and return a list of maps, with column header keys mapped to the corresponding
%% values for each row.
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-spec decode_file(File :: file:name_all()) -> mapped_csv().
decode_file(File) ->
    FD =
        case efile:open(File, [read, raw, {read_ahead, 4096}, {encoding, latin1}]) of
            {ok, Fd0} -> Fd0;
            {error, Reason} -> error({Reason, {file, File}})
        end,
    try
        {ok, Header, _Comments} = find_csv_header(FD, []),
        map_csv_entries(FD, Header, [])
    after
        file:close(FD)
    end.

%%-------------------------------------------------------------------
%% @param File CSV file to be decoded
%% @param Header List of column head type tuples consisting of a name and mapped type for values,
%% or key name atoms, which default to strings.
%% @doc Decode a csv file with the supplied column head keys and value types
%%
%% Read a csv file and return a list of maps, with the supplied header keys mapped to the
%% corresponding values converted to the specified `Type' for each row. Undefined values are always
%% the atom `undefined'.
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-spec decode_file(File :: file:name_all(), Header :: column_header()) -> mapped_csv().
decode_file(File, Header) ->
    FD =
        case file:open(File, [read, raw, {read_ahead, 4096}, {encoding, latin1}]) of
            {ok, Fd0} -> Fd0;
            {error, Reason} -> error({Reason, {file, File}})
        end,
    KeyMap = map_csv_entries(FD, Header, []),
    file:close(FD),
    KeyMap.

%%-------------------------------------------------------------------
%% @param Data iolist to be decoded
%% @param Header List of column head type tuples consisting of a name and mapped type for values,
%% or key name atoms, which default to strings.
%% @doc Decode an iolist with the supplied column head keys and value types
%%
%% Convert an iolist to a list of mapped entries, with the supplied header keys mapped to the
%% corresponding values converted to the specified `Type' for each row. Undefined values are always
%% the atom `undefined'.
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-spec decode_iolist(Data :: iolist(), Header :: column_header()) -> mapped_csv().
decode_iolist(Data, Header) ->
    Rows = string:split(Data, "\n", all),
    decode_iolist(Rows, Header, []).

%%===================================================================
%% Internal Functions
%%===================================================================

-spec map_csv_entries(Fd1 :: file:io_device(), Header :: column_header(), Acc :: mapped_csv() | []) ->
    MappedCSV :: mapped_csv().
map_csv_entries(Fd1, Header, Acc) ->
    %% TODO: Make this AtomVM compatible through efile module using posix file functions
    %%  to replace the use of file:read_line/1 on "ATOM".
    case file:read_line(Fd1) of
        {ok, [$# | _]} ->
            map_csv_entries(Fd1, Header, Acc);
        {ok, "\n"} ->
            map_csv_entries(Fd1, Header, Acc);
        {ok, Data} ->
            Map = csv_row_to_map(Data, Header),
            map_csv_entries(Fd1, Header, [Map | Acc]);
        eof ->
            lists:reverse(Acc);
        {error, Reason} ->
            error({"Failed to map line in csv file", Reason})
    end.

-spec decode_iolist(Rows :: iolist(), Header :: column_header(), Acc :: [map()] | []) ->
    [map()] | [].
decode_iolist([], _Header, Acc) ->
    lists:reverse(Acc);
decode_iolist([Line | Rows], Header, Acc) ->
    case Line of
        "\n" ->
            decode_iolist(Rows, Header, Acc);
        "" ->
            decode_iolist(Rows, Header, Acc);
        [$# | _] ->
            decode_iolist(Rows, Header, Acc);
        Line ->
            decode_iolist(Rows, Header, [csv_row_to_map(Line, Header) | Acc])
    end.

-spec csv_row_to_map(Line :: string() | binary(), Header :: column_header()) -> map().
csv_row_to_map(Line, Header) when is_binary(Line) ->
    csv_row_to_map(binary_to_list(Line), Header);
csv_row_to_map(Line, Header) ->
    Fields = string:split(Line, ",", all),
    KVlist = lists:zip(Header, [string:trim(V) || V <- Fields], {pad, {undefined, undefined}}),
    DecodedLists = decode_values(KVlist),
    maps:from_list(DecodedLists).

-spec decode_values(KVlist :: list({ColumnHead :: column_head(), RawValue :: raw_value()})) ->
    Decoded :: list({key(), value()}).
decode_values(KVlist) ->
    decode_values(KVlist, []).

-spec decode_values(
    KVlist :: list({ColumnHead :: column_head(), RawValue :: raw_value()}),
    Acc :: list({Name :: key(), DecodedValue :: value()} | none())
) -> Decoded :: list({key(), value()}).
decode_values(KVlist, Acc) ->
    case KVlist of
        [] ->
            lists:reverse(Acc);
        [Entry | List] ->
            E = maybe_decode_value(Entry),
            decode_values(List, [E | Acc])
    end.

-spec maybe_decode_value({Key :: column_head(), Value :: raw_value()}) ->
    Tuple :: {Name :: atom(), DecodedValue :: value()}.
maybe_decode_value({Key, Value}) when is_binary(Value) ->
    maybe_decode_value({Key, binary_to_list(Value)});
maybe_decode_value({Key, ""}) when is_tuple(Key) ->
    maybe_decode_value({Key, undefined});
maybe_decode_value({Key, ""}) ->
    {Key, undefined};
maybe_decode_value({Key, Value}) ->
    case Key of
        {KeyName, Type} when is_atom(KeyName) ->
            {KeyName, do_decode_value(Value, Type)};
        Key when is_atom(Key) ->
            {Key, Value};
        _ ->
            error({invalid_key, Key})
    end.

-spec do_decode_value(Value :: raw_value(), Type :: mapped_type()) -> value().
do_decode_value(Value, Type) ->
    case Type of
        integer ->
            case Value of
                [] ->
                    undefined;
                undefined ->
                    undefined;
                _ ->
                    case eee_lib:parse_int_string(Value) of
                        {ok, Int} ->
                            Int;
                        {error, Reason} ->
                            error({decode_int_fail, Reason})
                    end
            end;
        string ->
            Value;
        binary ->
            case Value of
                undefined -> undefined;
                _ -> list_to_binary(Value)
            end;
        atom ->
            case Value of
                Value when is_atom(Value) -> Value;
                _ ->
                    try
                        list_to_existing_atom(Value)
                    catch
                        error:badarg ->
                            list_to_atom(Value)
                    end
            end;
        _ ->
            error({unsupported_decode_type, Type})
    end.

-spec find_csv_header(FD :: file:io_device(), Acc :: list()) ->
    {ok, [key()], Comments :: [string() | binary()] | []}.
find_csv_header(FD, Acc) ->
    Headings =
        %% TODO: Replace the use of file:read_line/1 with efile functions with posix option
        case file:read_line(FD) of
            {ok, "\n"} ->
                {none, "\n"};
            {ok, [$# | Header] = H} ->
                CSVHead = string:split(Header, ",", all),
                case length(CSVHead) of
                    Len when Len < 2 ->
                        {none, H};
                    _ ->
                        CSVHead
                end;
            {ok, Head} ->
                CSVHead = string:split(Head, ",", all),
                case length(CSVHead) of
                    Len when Len < 2 ->
                        file:close(FD),
                        error(no_csv_header);
                    _ ->
                        CSVHead
                end;
            eof ->
                file:close(FD),
                error(no_csv_header);
            {error, Reason} ->
                file:close(FD),
                error({find_csv_header_failed, Reason})
        end,
    case Headings of
        {none, Comment} ->
            find_csv_header(FD, [Comment | Acc]);
        _ ->
            ParsedHeader = [column_head_to_atom(Field) || Field <- Headings],
            {ok, ParsedHeader, lists:reverse(Acc)}
    end.

-spec column_head_to_atom(String :: string()) -> ColHead :: atom().
column_head_to_atom(String) ->
    case string:trim(String) of
        "" ->
            undefined;
        KeyName ->
            try
                list_to_existing_atom(string:lowercase(KeyName))
            catch
                error:badarg ->
                    list_to_atom(string:lowercase(KeyName))
            end
    end.
