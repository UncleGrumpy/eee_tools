%% Entry logic for NVS partition generator
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
%% Non-volatile storage entry handing functions.
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-module(nvs_entry).
-include("esp_nvs.hrl").

%% TODO: add support for all types, not just AtomVM supported ones.
-export([
    encode/5,
    encode_maps/1
]).

-export_type([
    packed_kv/0,
    ns_idx/0
]).

-define(PAD, <<16#ff>>).
-define(PAD_KEY, <<16#00>>).
-define(BLOB_SPAN_MIN, 2).
-define(BLOB_HEADER_SIZE, 1).

-type packed_kv() :: binary().
%% 32-byte aligned binary, padded if necessary.
-type ns_idx() :: 0..254.

%% Encodes an NVS packed_kv, including CRC

%%===================================================================
%% API Functions
%%===================================================================

%%----------------------------------------------------------------------------
%% @param EntryMap an esp_nvs:entry_list/0
%% @returns
%% @doc Encodes a list of `t:esp_nvs:entry_map/0' to a list of binary encoded entries
%%
%% This function will take a list of `t:esp_nvs:entry_map/0' and will encode all of the entries into
%% a list of `nvs_entry:packed_kv()' starting from name space index 0. No `ns_idx/0' is returned,
%% so no further key can be safely added using `encode/5' unless the last namespace is known.
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec encode_maps(KVmaps :: esp_nvs:entry_list()) -> EntryList :: [nvs_entry:packed_kv()].
encode_maps(KVmaps) ->
    encode_maps(KVmaps, 0, []).

-spec encode_maps(
    Entries :: esp_nvs:entry_list() | [],
    NsIdx :: nvs_entry:ns_idx(),
    Acc :: [nvs_entry:packed_kv()] | []
) -> [nvs_entry:packed_kv()].
encode_maps([], _NsIdx, Acc) when length(Acc) >= 1 ->
    lists:reverse(Acc);
encode_maps([], _NsIdx, []) ->
    error({badarg, "no entries"});
encode_maps([Entry | Entries], NsIdx, Acc) ->
    Key = maps:get(key, Entry),
    Type = maps:get(type, Entry),
    Encoding = maps:get(encoding, Entry),
    Value = maps:get(value, Entry),
    {BinEntry, NewNs} = nvs_entry:encode(Key, Type, Encoding, Value, NsIdx),
    encode_maps(Entries, NewNs, [BinEntry | Acc]).

%%-----------------------------------------------------------------------------
%% @param Key Name of the key, used during retrieval
%% @param Type `data', `file' or `namespace'
%% @param Encoding encoding type `binary' for entries or `u8' for namespaces
%% @param Value the data to be stored under the given `Key'
%% @param NsIdx the current namespace index value
%% @returns {PackedEntry, NameSpace} or raises an error
%% @doc Encodes a key-value pair, including CRC32, into an NVS entry.
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
%% 32-Byte packed_kv header reference:
%% <<NameSpace:1/byte, Type:1/byte, Span:1/byte, ChunkIndex:1/byte, Crc32:4/byte, Key:16/byte, Value:8/byte>>
-spec encode(
    Key :: esp_nvs:entry_key() | binary(),
    Type :: esp_nvs:entry_type(),
    Encoding :: esp_nvs:encoding(),
    Value :: esp_nvs:entry_value(),
    NsIdx :: ns_idx()
) -> {PackedEntry :: packed_kv(), NameSpace :: ns_idx()}.
encode(Key, Type, Encoding, Value, NsIdx) when is_atom(Key) ->
    encode(atom_to_binary(Key), Type, Encoding, Value, NsIdx);
encode(Key, namespace, _Encoding, _Value, NsIdx) when NsIdx =< 254 ->
    NewNsIdx = NsIdx + 1,
    KeyBin = pad_key(Key),
    Val = pad_primitive(<<NewNsIdx:8>>),
    PreCrc = <<
        16#00:1/unsigned-integer-unit:8,
        16#01:1/unsigned-integer-unit:8,
        16#01:1/unsigned-integer-unit:8,
        16#ff:1/unsigned-integer-unit:8,
        0:32,
        KeyBin:16/binary,
        Val:8/binary
    >>,
    Crc = compute_crc32_for_header(PreCrc),
    {
        <<16#00:8, 16#01:8, 16#01:8, 16#ff:8, Crc:1/little-unsigned-integer-unit:32,
            KeyBin:16/binary, Val:8/binary>>,
        NewNsIdx
    };
encode(Key, namespace, _Encoding, _Value, NsIdx) ->
    error({namespace_index_exhausted, {NsIdx, Key}});
encode(Key, data, binary, Value, NsIdx) when is_list(Value) ->
    Data =
        case filelib:is_file(Value) of
            true ->
                case efile:read(Value) of
                    {ok, Data0} ->
                        Data0;
                    {error, Reason} ->
                        error({read_data_file, Reason})
                end;
            false ->
                list_to_binary(Value)
        end,
    encode(Key, data, binary, Data, NsIdx);
encode(Key, data, binary, Value, NsIdx) when is_binary(Value) andalso byte_size(Value) =< 4000 ->
    %% pad Value data to 32-byte aligned block and calculate CRC needed for data header
    {Span0, PaddedBinValue} = pad_entry(Value),
    DataCrc = ecrc:crc32_le(Value),

    %% create binary data header
    KeyBin = pad_key(Key),
    BinSize = byte_size(Value),
    %% For binary blob header the 8 byte "Value" is (Reserved = <<16#ff, 16#ff>>):
    %% <<Size:1/unsigned-integer-unit:16, Reserved:2/byte, DataCrc32:1/unsigned-integer-unit:32>>
    BlobInfo =
        <<BinSize:1/unsigned-integer-little-unit:16, 16#ffff:16,
            DataCrc:1/unsigned-integer-little-unit:32>>,
    HeadPreCrc = <<
        NsIdx:1/unsigned-integer-unit:8,
        16#42:1/unsigned-integer-unit:8,
        Span0:1/unsigned-integer-unit:8,
        16#00:1/unsigned-integer-unit:8,
        0:32,
        KeyBin:16/binary,
        BlobInfo:8/binary
    >>,
    HeadCrc = compute_crc32_for_header(HeadPreCrc),
    BinaryHead =
        <<NsIdx:8, 16#42:8, Span0:8, 16#00:8, HeadCrc:1/little-unsigned-integer-unit:32,
            KeyBin:16/binary, BlobInfo:8/binary>>,

    %% create binary data footer
    %%  <<Size:4/byte, ChunkCount:1/byte, ChunkStart:1/byte, Rsv:2/byte>>
    BlobIdx =
        <<BinSize:1/unsigned-integer-little-unit:32, 16#01, 16#00, 16#ffff:16>>,
    FooterPreCrc = <<
        NsIdx:1/unsigned-integer-unit:8,
        16#48:1/unsigned-integer-unit:8,
        16#01:1/unsigned-integer-unit:8,
        16#ff:1/unsigned-integer-unit:8,
        0:32,
        KeyBin:16/binary,
        BlobIdx:8/binary
    >>,
    FooterCrc = compute_crc32_for_header(FooterPreCrc),
    BinaryFooter =
        <<NsIdx:8, 16#48:8, 16#01:8, 16#ff:8, FooterCrc:1/little-unsigned-integer-unit:32,
            KeyBin:16/binary, BlobIdx:8/binary>>,
    BlobLen = ((Span0 - 1) * ?NVS_BLOCK_SIZE),

    %% Assemble complete binary data packed_kv
    {<<BinaryHead:32/binary, PaddedBinValue:BlobLen/binary, BinaryFooter:32/binary>>, NsIdx};
encode(Key, data, _Encoding, Atom, NsIdx) when is_atom(Atom) ->
    encode(Key, data, _Encoding, atom_to_binary(Atom), NsIdx);
encode(Key, data, binary, Value, _NsIdx) when is_binary(Value) ->
    error({nvs_binary_size_exceeded, {Key, Value}});
encode(Key, data, Encoding, Value, NsIdx) ->
    display_warning(
        "Encoding ~w found, AtomVM only supports binary blob retrieval,\n"
        "~w will be encoded with term_to_binary/1.\n"
        "The key ~w can be decoded with binary_to_term/1 after retrieval.\n",
        [Encoding, Value, Key]
    ),
    encode(Key, data, binary, term_to_binary(Value), NsIdx).

%%===================================================================
%% Internal Functions
%%===================================================================

%% CRC32 calculation for the header
-spec compute_crc32_for_header(Entry :: packed_kv()) -> CRC32 :: ecrc:crc32_checksum().
compute_crc32_for_header(Entry) ->
    %% CRC is calculated over Header (first 4 bytes), then key/value (bytes 8 to end of data), little-endian
    <<Header:4/binary, _OldCrc:4/binary, DataRest:24/binary>> = Entry,
    CrcData = <<Header:4/binary, DataRest:24/binary>>,
    ecrc:crc32_le(CrcData).

%% Pad (<<16#ff>>) binary values to 32 bytes
-spec pad_entry(Entry :: packed_kv()) -> {Span :: 1..28, PaddedEntry :: binary()}.
pad_entry(Entry) ->
    DataSize = byte_size(Entry),
    {PadLen, Span} =
        case DataSize > ?NVS_BLOCK_SIZE of
            true ->
                PadSize =
                    case DataSize rem ?NVS_BLOCK_SIZE of
                        0 -> 0;
                        Rem -> ?NVS_BLOCK_SIZE - Rem
                    end,
                Blocks =
                    (((DataSize + ?NVS_BLOCK_SIZE - 1) div ?NVS_BLOCK_SIZE) + ?BLOB_HEADER_SIZE),
                {PadSize, Blocks};
            false ->
                {?NVS_BLOCK_SIZE - DataSize, ?BLOB_SPAN_MIN}
        end,
    Pad = binary:copy(?PAD, PadLen),
    {Span, <<Entry:DataSize/binary, Pad:PadLen/binary>>}.

%% Pad (<<16#ff>>) primitive values to 8 bytes
-spec pad_primitive(Value :: binary()) -> PaddedValue :: esp_nvs:entry_value().
pad_primitive(Value) ->
    DataSize = byte_size(Value),
    case DataSize of
        Short when Short < 8 ->
            PadLen = 8 - Short,
            Pad = binary:copy(?PAD, PadLen),
            <<Value:DataSize/binary, Pad/binary>>;
        8 ->
            Value;
        _ ->
            error({value_exceeds_size_limit, Value})
    end.

%% Key padding (<<16#00>>) or truncation, convert binary "Key" of any length to 16 bytes.
-spec pad_key(Key :: binary()) -> esp_nvs:entry_key().
pad_key(Key) ->
    KeyLen = byte_size(Key),
    case KeyLen > ?NVS_KEY_CHARS of
        true ->
            Truncated = binary:part(Key, 0, ?NVS_KEY_CHARS),
            display_warning(
                "Long key detected, ESP-IDF supports key lengths up to 16 bytes. The key\n"
                "~w has been truncated to\n"
                "~w, beware of name collisions, each key can only be used\n"
                "once per namespace.\n",
                [Key, Truncated]
            ),
            <<Truncated/binary, 0>>;
        false ->
            if
                KeyLen =:= ?NVS_KEY_CHARS ->
                    <<Key/binary, 0>>;
                true ->
                    PadLen = ?NVS_KEY_CHARS + 1 - KeyLen,
                    Pad = binary:copy(?PAD_KEY, PadLen),
                    <<Key:KeyLen/binary, Pad:PadLen/binary>>
            end
    end.

-ifdef(TEST).
display_warning(_Fmt, _Args) ->
    ok.
-else.
display_warning(Fmt, Args) ->
    io:format(Fmt, Args).
-endif.
