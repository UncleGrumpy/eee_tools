%% Page logic for NVS partition generator
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
%% @doc APIs for Non-Volatile Storage pages.
%%
%% Interfaces for formatting NVS data into pages suitable for the `nvs' partition on ESP32 devices.
%% @since 0.1.0
%% @end
%%-------------------------------------------------------------------
-module(nvs_page).
-include("esp_nvs.hrl").

-export([
    init/1, init/2,
    new_page/2,
    new_page/3,
    insert_entries/3,
    build_partition/2,
    size_to_free_pages/1
]).

-export_type([page/0]).

-type page() :: #page{}.
%% A non-volatile storage page record

-define(V1_MAX_ENTRY_SIZE, 1984 + 64).
%% 1984 bytes max data + 64 bytes header/footer

%%-----------------------------------------------------------------------------
%% @param Size NVS partition size
%% @returns an `ok' tuple with an initialized page record
%% @doc Use this function to initialize a version 2 NVS binary partition
%%
%% This will initialize the NVS page allocator with version 2 formatting, this is the version used
%% by AtomVM.
%%
%% @equiv `init(2, Size)'
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec init(Size :: pos_integer()) ->
    {ok, {page(), NumPages :: pos_integer()} | {readonly, {page(), NumPages :: pos_integer()}}}.
init(Size) ->
    init(2, Size).

%%-----------------------------------------------------------------------------
%% @param Version the NVS subsystem version to use
%% @param Size NVS partition size
%% @returns an `ok' tuple or raises an error
%% @doc Use this function to initialize an NVS binary partition
%%
%% This will initialize the NVS page allocator, and return a tuple with a new page record for NVS
%% entries, along with the number of free pages. All subsequent pages should be allocated with
%% `f:new_page/2' or `f:new_page/3'.
%%
%% If the partition is too small to support normal read and write operations (which requires a
%% minimum of 3 pages, one of which is reserved for swap), then the page-record tuple will be
%% wrapped in a tuple with `readonly'. For example:
%%
%%     `{ok, {readonly, {Page, 2}}}'
%%
%% Note: AtomVM uses version 2
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec init(Version :: 1 | 2, Size :: pos_integer()) ->
    {ok, {page(), NumPages :: pos_integer()} | {readonly, {page(), NumPages :: pos_integer()}}}.
init(Version, Size) ->
    case size_to_free_pages(Size) of
        {readonly, ROPages} ->
            Page = new_page(Version, 1, ROPages),
            {ok, {readonly, {Page, ROPages}}};
        NumPages ->
            Page = new_page(Version, 1, NumPages),
            {ok, {Page, NumPages}}
    end.

%%-----------------------------------------------------------------------------
%% @param PageNum the number of the page to be created
%% @param NumPages number of usable pages, not including the 1 mandatory swap page
%% @returns an initialized page record
%% @doc Generate a version 2 initialized page record
%%
%% @equiv `new_page(2, PageNum, NumPages)'
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec new_page(PageNum :: pos_integer(), NumPages :: pos_integer()) -> page().
new_page(PageNum, NumPages) ->
    new_page(2, PageNum, NumPages).

%%-----------------------------------------------------------------------------
%% @param Version NVS version format to use.
%% @param PageNum the number of the page to be created
%% @param NumPages total number of usable pages, not including the 1 mandatory swap page
%% @returns a new page record
%% @doc Generate a new page page record
%%
%% Using this function directly should not be necessary for most applications, `f:insert_entries/3'
%% will create new page as necessary.
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec new_page(Version :: 1 | 2, PageNum :: pos_integer(), NumPages :: pos_integer()) -> page().
new_page(Version, PageNum, NumPages) ->
    %% Generate a buffer to initialize the page with 16#ff following the header
    Buf0 = binary:copy(<<16#ff>>, ?NVS_PAGE_SIZE - ?NVS_BLOCK_SIZE),
    PageState = binary:encode_unsigned(16#fffffffe, little),
    Ver = encode_version(Version),
    Unused = binary:copy(<<16#ff>>, 19),
    HeadData = <<0:32, Ver:1/binary, Unused:19/binary>>,
    Crc = binary:encode_unsigned(ecrc:crc32_le(HeadData), little),
    PageBuf =
        <<PageState:4/binary, HeadData:24/binary, Crc:4/binary, Buf0/binary>>,
    #page{
        num_pages = NumPages, page_num = PageNum, version = Version, page_buf = PageBuf
    }.

%%-----------------------------------------------------------------------------
%% @param List of entries to add to the NVS partition
%% @param Record for the current active page
%% @param The accumulator for the added page records
%% @returns a list of page records
%% @doc Insert entries into page records
%%
%% Adds a list of entries to the current page record, adding pages as necessary on page over-flows,
%% and returns a list of page records that can be passed to `f:build_partition/2' to assemble a
%% binary partition.
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec insert_entries(
    Entries :: [nvs_entry:packed_kv()] | [],
    CurrPage :: nvs_page:page(),
    AccPages :: [nvs_page:page()]
) -> [nvs_page:page()].
insert_entries([], CurrPage, AccPages) ->
    Pages = [CurrPage | AccPages],
    lists:reverse(Pages);
insert_entries([Entry | _Rest], #page{version = Version} = _CurrPage, _Acc) when
    Version =:= 1 andalso byte_size(Entry) > ?V1_MAX_ENTRY_SIZE
->
    error({v1_blob_oversize, {binary_part(Entry, 8, 16), byte_size(Entry) - 64, "max: 1984"}});
insert_entries([Entry | Rest], CurrPage, AccPages) ->
    case insert_entry(Entry, CurrPage) of
        {ok, UpdatedPage} ->
            insert_entries(Rest, UpdatedPage, AccPages);
        {ok, LastPage, NewPage} ->
            insert_entries(Rest, NewPage, [LastPage | AccPages])
    end.

%%-----------------------------------------------------------------------------
%% @param Page record or list of page records to build the partition from
%% @param Size of the partition on flash
%% @returns A non-volatile storage partition, padded to the correct size if necessary.
%% @doc Generate a binary partition, suitable for flashing, from a list of page records.
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec build_partition(Pages :: nvs_page:page() | [nvs_page:page()], Size :: non_neg_integer()) ->
    binary().
build_partition(Pages, Size) when is_list(Pages) ->
    BinPages = lists:foldl(
        fun(Page, Acc) -> <<Acc/binary, (Page#page.page_buf)/binary>> end, <<>>, Pages
    ),
    BinLen = byte_size(BinPages),
    case BinLen =< Size of
        true ->
            PadSize = Size - BinLen,
            Padding = binary:copy(<<16#ff:8>>, PadSize),
            if
                BinLen =:= Size -> BinPages;
                true -> <<BinPages:BinLen/binary, Padding:PadSize/binary>>
            end;
        false ->
            error({partition_overflow, {BinLen, Size}})
    end;
build_partition(Page, Size) when is_record(Page, page) ->
    build_partition([Page], Size).

%%-----------------------------------------------------------------------------
%% @param Size NVS partition size, in bytes
%% @returns The number of pages, or `{readonly, NumPages}'
%% @doc Get the number of usable pages in an NVS partition
%%
%% The returned count will not include the swap page, which is required for writable NVS
%% partitions. Swap is not created when the partition size will only accommodate one or two pages.
%% @since 0.1.0
%% @end
%%-----------------------------------------------------------------------------
-spec size_to_free_pages(Size :: pos_integer()) ->
    NumPages :: pos_integer() | {readonly, NumPages :: pos_integer()}.
size_to_free_pages(Size) when Size =< 2 * ?NVS_PAGE_SIZE ->
    case (Size rem ?NVS_PAGE_SIZE) of
        0 ->
            {readonly, (Size div ?NVS_PAGE_SIZE)};
        Invalid ->
            error({invalid_nvs_size, Invalid})
    end;
size_to_free_pages(Size) ->
    case (Size rem ?NVS_PAGE_SIZE) of
        0 ->
            (Size div ?NVS_PAGE_SIZE) - 1;
        Invalid ->
            error({invalid_nvs_size, Invalid})
    end.

-spec insert_entry(Packed :: nvs_entry:packed_kv(), Page :: page()) ->
    {ok, Page :: page()} | {ok, Page :: page(), NewPage :: page()}.
insert_entry(Packed, Page) ->
    {Page0, NewPage, Offset, NewOffset} = find_active_page_offsets(Packed, Page),
    {CurPage, OldPage} =
        case NewPage of
            true -> {set_page_full(Page0), undefined};
            false -> {Page0, undefined};
            NewPage0 -> {NewPage0, set_page_full(Page0)}
        end,

    Pre = binary:part(CurPage#page.page_buf, 0, Offset),
    <<Header:32/binary, EntryBitmap:32/binary, Entries/binary>> = Pre,
    Tail = binary:part(
        CurPage#page.page_buf,
        NewOffset,
        ?NVS_PAGE_SIZE - NewOffset
    ),
    NumBlocks = byte_size(Packed) div 32,
    EntryMask = update_entry_mask(NumBlocks, CurPage#page.offset, EntryBitmap),
    NewBuf =
        <<Header:32/binary, EntryMask:32/binary, Entries/binary, Packed/binary, Tail/binary>>,
    case OldPage of
        OldPage0 when is_record(OldPage0, page) ->
            {ok, OldPage0, CurPage#page{page_buf = NewBuf, offset = NewOffset}};
        undefined ->
            {ok, CurPage#page{offset = NewOffset, page_buf = NewBuf}}
    end.

-spec update_entry_mask(
    Blocks :: pos_integer(), Offset :: pos_integer(), EntryTable :: binary()
) -> NewTable :: binary().
update_entry_mask(0, _Offset, <<EntryTable:32/binary-little>>) ->
    <<EntryTable:32/binary-little>>;
update_entry_mask(Blocks, Offset, EntryTable) ->
    EntryNum = ((Offset - 64) div 32),
    Shift = 256 - (EntryNum * 2) - 2,
    EditTable = eee_lib:reverse_endian(EntryTable),
    <<Head:Shift, _TargetBits:2, Tail/bitstring>> = EditTable,
    %% ESP-IDF NVS entry bitmap format. 2 bits per entry: 00=empty, 10=written, 11=erased
    EditedTable = <<Head:Shift, 2#10:2, Tail/bitstring>>,
    update_entry_mask(Blocks - 1, Offset + 32, eee_lib:reverse_endian(EditedTable)).

-spec encode_version(Version :: 1 | 2) -> esp_nvs:version().
encode_version(1) -> <<16#ff>>;
encode_version(2) -> <<16#fe>>.

-spec find_active_page_offsets(Entry :: nvs_entry:packed_kv(), Page :: page()) ->
    {
        Page :: page(),
        NewPage :: page() | boolean(),
        Offset :: pos_integer(),
        NextOffset :: pos_integer()
    }.
find_active_page_offsets(Entry, Page) ->
    Offset = Page#page.offset,
    NewOffset = Offset + byte_size(Entry),
    Size = byte_size(Entry),
    case NewOffset of
        NewOffset when NewOffset > ?NVS_PAGE_SIZE ->
            if
                (Page#page.page_num + 1) > Page#page.num_pages -> error(nvs_partition_overflow);
                true -> ok
            end,
            NewPage0 = new_page(Page#page.version, Page#page.page_num + 1, Page#page.num_pages),
            NewOffset1 = NewPage0#page.offset,
            NewPage = NewPage0#page{
                ns_idx = Page#page.ns_idx
            },
            {Page, NewPage, NewOffset1, NewOffset1 + Size};
        NewOffset2 when NewOffset2 =:= ?NVS_PAGE_SIZE ->
            {Page, true, Offset, NewOffset2};
        _ ->
            {Page, false, Offset, NewOffset}
    end.

-spec set_page_full(Page :: page()) -> UpdatedPage :: page().
set_page_full(Page) ->
    PageFull = binary:encode_unsigned(16#fffffffc, little),
    <<_OldState:4/binary, PageData:4092/binary>> = Page#page.page_buf,
    Buff = <<PageFull:4/binary, PageData:4092/binary>>,
    Page#page{page_buf = Buff}.
