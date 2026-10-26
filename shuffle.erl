%%%                                             %
%%  SPDX-License-Identifier: Apache-2.0
%%
%%  Copyright Ericsson AB 2026.
%%  All Rights Reserved.
%%
%%  Licensed under the Apache License,
%%  Version 2.0 (the "License");
%%  you may not use this file except
%%  in compliance with the License.
%%  You may obtain a copy of the License at
%%
%%  http://www.apache.org/licenses/LICENSE-2.0
%%
%%  Unless required by applicable law
%%  or agreed to in writing, software
%%  distributed under the License
%%  is distributed on an "AS IS" BASIS,
%%  WITHOUT WARRANTIES OR CONDITIONS
%%  OF ANY KIND, either express or implied.
%%
%%  See the License for the specific
%%  language governing permissions and
%%  limitations under the License.
%%
-module(shuffle).

%%%
%%  Author: Raimo Niskanen, Erlang/OTP
%%
%%  Erlang module that creates
%%  the benchmark data for my presentation
%%  "Do the List Shuffle".
%%
%%  Start an Erlang/OTP 29.0 or later shell,
%%  with this module in the current
%%  working directory:
%%  1> c(shuffle).
%%  2> shuffle:gp().
%%
%%  That takes a while and creates a file
%%  "shuffle.dat" in the current
%%  working directory.
%%
%%  Next, have a look in the GnuPlot script
%%  "shuffle.gp".

-export(        % Shuffle algorithms:
   [fya/1,      % Fisher-Yates with 'array'
    fym/1,      % Fisher-Yates with map()
    lks0/1,     % Tag, lists:keysort/1, compr
    lks/1,      % Tag, lists:keysort/1
    mko/1,      % Tag, map() internal key order
    rrs0/1,     % Recursive Split and Collect
    rrs/1]).    %          —"—     by coin flip

-export(        % Additional shuffle algorithms:
   [lks2/1,     % Tag, lists:keysort/1 optimized
    mko2/1,     % Tag, map() ordered key order
    rins/1,     % Random Insert
    fyct2/1,    % Fisher-Yates with ctree:2
    fyct4/1,    % Fisher-Yates with ctree:4
    fyct8/1,    % Fisher-Yates with ctree:8
    fyct16/1]). % Fisher-Yates with ctree:16

%% Benchmark API and utilities
-export(
   [p/0, p/1, p/2, p/3,   % Performance summary
    gp/0,gp/1,gp/2,gp/5,  % Generate GnuPlot data
    t/1, t/2, t/3, tc/3,  % Measure one shuffle
    %%
    li/1,                 % List of integers
    rbool/2,              % Bad example
    rrange/1, rword/1,    % PRNG speed tests
    reverse/1]).          %      -"-

%% Performance summary p/0,1 defaults
-define(LEN, 1_000_000).  % Default list length
-define(CNT, 4).          % Default repeat

%% GnuPlot data gp/0..2 defaults
-define(GP_LEN, (1 bsl 3)).
-define(GP_CNT, (1 bsl (20-3))).
-define(GP_MUL, 2).

%% PRNG size
-define(PRNG_BITS, 56).

%%  Random integer 0 .. M-1
rint(M) ->
    case rand:uniform(M) of
        %% Guide the JIT – integer limits
        V when is_integer(V, 1, M) ->
            V - 1
    end.

%%  Random word, 0 .. 2^PRNG_BITS - 1
rint() -> rint(1 bsl ?PRNG_BITS).

-compile({inline, [rint/0, rint/1]}).



%%%
%%  Fisher-Yates with 'array'

fya(L) ->
    A = array:from_list(L),
    N = array:size(ds(A)),
    fya(A, N, []).

fya(_, 0, Acc) -> Acc;
fya(A, N, Acc) ->
    K = rint(N),
    X = array:get(K, A),
    Y = array:get(N-1, A),
    fya(array:set(K, Y, A), N-1, [X | Acc]).


%%%
%%  Fisher-Yates with map()

fym(L) ->
    TL = lists:enumerate(0, L),
    M = maps:from_list(TL),
    N = maps:size(ds(M)),
    fym(M, N, []).

fym(_, 0, Acc) -> Acc;
fym(M, N, Acc) ->
    K = rint(N),
    N_1 = N - 1,
    #{ K := X, N_1 := Y } = M,
    fym(M#{ K := Y }, N_1, [X | Acc]).


%%%
%%  Randomize and sort, "One"-liner

lks0(L) ->
    [Y || {_, Y} <-
              lists:keysort(
                1, [{rint(), X} || X <- L])].

%%%
%%  Randomize and sort
%%
%%  Shuffle duplicates while untagging.

lks(L) -> lks(L, []).

lks(L, Acc) ->
    TL1 = rtag(L, []),
    TL2 = lists:keysort(1, ds(TL1)),
    untag(TL2, Acc, -1).

rtag([], Acc) -> Acc;
rtag([X | L], Acc) ->
    rtag(L, [{rint(), X} | Acc]).

untag([{T, X} | TL], Acc, T) ->
    %% Duplicate tag
    duplicates(TL, tl(Acc), T, [X, hd(Acc)]);
untag([{T, X} | TL], Acc, _) ->
    untag(TL, [X | Acc], T);
untag([], Acc, _) -> Acc.

%% Collect all duplicate tags
duplicates([{T, X} | TL], Acc, T, Dups) ->
    duplicates(TL, Acc, T, [X | Dups]);
%% Shuffle duplicates
duplicates([{T, X} | TL], Acc, _, Dups) ->
    untag(TL, [X | lks(Dups, Acc)], T);
duplicates([], Acc, _, Dups) ->
    lks(Dups, Acc).


%%%
%%  Randomize and use map() key order

mko(L) -> mko(L, #{}).

mko([], M) ->
    maps:values(ds(M));     % In maps key order
mko([X | L] = X_L, M) ->
    T = rint(),             % Random tag
    case M of
        %% Retry if duplicate tag
        #{ T := _ } -> mko(X_L, M);
        #{}         -> mko(L, M#{ T => X })
    end.


%%%
%%  Recursive Random Split (Knuth split)

rrs0(L) -> rrs0(L, []).

rrs0([], Acc) -> Acc;
rrs0([X], Acc) -> [X | Acc];
rrs0([_|_] = L, Acc0) ->
    N = length(L),
    P = N div 2,
    {A, B} = krsplit(L, N, P),
    Acc1 = rrs0(A, Acc0),
    rrs0(B, Acc1).

%%% Knuth's random selection
%%  – from L that has length N,
%%    with equal probability,
%%    select P random elements.

krsplit(L, N, P) ->
    krsplit(L, N, P, [], []).

krsplit(L, _, 0, A, B) ->
    {A, lists:reverse(L, B)};
krsplit([X | L], N, P, A, B) ->
    K = rint(N),
    if  K < P ->
            krsplit(L, N-1, P-1, [X|A], B);
        true ->
            krsplit(L, N-1, P, A, [X|B])
    end.


%%%
%%  Recursive Random Split (coin flip)

rrs(L) ->
    S = 1, % Empty bit cache word
    {_S, Acc} = rrs(L, S, []),
    Acc.

rrs([], S, Acc) -> {S, Acc};
rrs([X], S, Acc) -> {S, [X | Acc]};
rrs([_|_] = L, S, Acc) ->
    {S1, Zero, One} = brsplit(L, S, [], []),
    {S2, Acc2} = rrs(Zero, S1, Acc),
    rrs(One, S2, Acc2).

-compile({inline, [rbits/0]}).
%% Random bit cache word (top bit marks end)
rbits() ->
    B = 1 bsl ?PRNG_BITS,
    rint(B) bor B.

%%% Split by random bit from bit cache word
brsplit([], S, Zero, One) -> {S, Zero, One};
brsplit([_|_] = L, 1, Zero, One) ->
    brsplit(L, rbits(), Zero, One);
brsplit([X | L], S0, Zero, One)
%%% Guide the JIT to smallnum bit cache
  when is_integer(S0, 2, (1 bsl 57)-1) ->
    S1 = S0 bsr 1,
    case S0 band 1 of
        0 -> brsplit(L, S1, [X | Zero], One);
        1 -> brsplit(L, S1, Zero, [X | One])
    end.


%%% PRNG speed tests

%%  Random numbers in Range
rrange(Rs) -> rrange(Rs, []).

rrange([], Acc) -> Acc;
rrange([R | Rs], Acc)
  when is_integer(R, 0, (1 bsl ?PRNG_BITS)-1) ->
    rrange(Rs, [rint(R + 1) | Acc]).

%%  Random words
rword(Rs) -> rword(Rs, []).

rword([], Acc) -> Acc;
rword([R | Rs], Acc)
  when is_integer(R, 0, (1 bsl ?PRNG_BITS)-1) ->
    rword(Rs, [rint() | Acc]).

%%  Minimal work – reverse a list.
reverse(L) -> reverse(L, []).

reverse([], Acc) -> Acc;
reverse([H | T], Acc) -> reverse(T, [H | Acc]).


%%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  Bonus algorithms


%%%
%%  Randomize and use ordered map() key order

mko2(L) -> mko2(L, #{}).

mko2([], M) ->
    maps:fold(
      fun (_, X, Acc) -> [X | Acc] end, [],
      maps:iterator(ds(M), ordered));
mko2([X | L] = X_L, M) ->
    T = rint(),
    case M of
        #{ T := _ } -> mko2(X_L, M);
        #{}         -> mko2(L, M#{ T => X })
    end.


%%%
%%  Randomize and sort
%%
%%  Shuffle duplicates while untagging,
%%  optimized as if in the 'rand' module
%%

lks2(L) ->
    {#{next := Next}, R} =
        %% Get the current PRNG state
        rand:seed_s(
          case rand:export_seed() of
              undefined   -> default;
              ExportState -> ExportState
          end),
    tl(lks2(L, Next, R, [])).

lks2(L, Next, R0, Acc) ->
    [R1 | TL0] = lks2_tag(L, Next, R0, []),
    TL1 = lists:keysort(1, ds(TL0)),
    lks2_untag(TL1, Next, R1, Acc, -1).

lks2_tag([X | L], Next, R0, TL) ->
    {T, R1} = Next(R0),
    lks2_tag(L, Next, R1, [{T,X} | TL]);
lks2_tag([], _Next, R, TL)          -> [R | TL].

lks2_untag([{Ty,Y} | TL], Next, R, Acc, Tx) ->
    if  Ty =:= Tx ->
            lks2_dups(
              TL, Next, R, tl(Acc), Ty,
              [Y, hd(Acc)]);
        true ->
            lks2_untag(
              TL, Next, R, [Y | Acc], Ty)
    end;
lks2_untag([], _Next, R, Acc, _) ->    [R | Acc].

lks2_dups(
  [{Tz,Z} | TL], Next, R0, Acc0, Ty, Dups) ->
    if  Tz =:= Ty ->
            lks2_dups(
              TL, Next, R0, Acc0, Tz,
              [Z | Dups]);
        true ->
            %% "Never" happens
            erlang:display(duplicate),
            [R1 | Acc1] =
                lks2(Dups, Next, R0, Acc0),
            lks2_untag(
              TL, Next, R1, [Z | Acc1], Tz)
    end;
lks2_dups([], Next, R, Acc, _, Dups) ->
    erlang:display(duplicate), % "Never" happens
    lks2(Dups, Next, R, Acc).


%%% Random Insert
%%
%%  Insert each element in a random position.
%%
%%  This is essentially a way to select one of
%%  all possible permutations for a list with
%%  one more element.

rins(L) when is_list(L) ->
    case L of
        []          -> L;
        [_]         -> L;
        [A, B | Es] ->
            %% Start tree, choose a
            %% permutation
            case rint(2) of
                1 -> rins_shuffle(Es, [B|A], 2);
                0 -> rins_shuffle(Es, [A|B], 2)
            end
    end.

rins_shuffle([], T, N) ->
 rins_to_list([], ds(T), N);
rins_shuffle([E | Es], T, N)
  when is_integer(N), N >= 1 ->
    %% Loop with E inserted in a random pos
    N_1 = N + 1,
    rins_shuffle(
      Es, rins_insert(E, T, N, rint(N_1)), N_1).

%%  A binary tree for insertion in
%%  (before) a position.
%%
%%  A node {M, L, R} has got M elements
%%  in subtree L.  To interpret R, the total
%%  number of elements  in the node, N,
%%  has to be known, denoted as {M, L, R}:N.
%%
%%  As an optimization, a node [A|B] represents
%%  {1, A, B}:2 where A and B are elements.
%%
%%  There are no other nodes with M < 2,
%%  from which follows that for {N-1, L, B}:N,
%%  L is a subtree and B is an element.
%%
rins_insert(E, [A|B], 2, I)
  when is_integer(I, 0, 2) ->
    case I of
        0 ->
            {2, [E|A], B};
        1 ->
            {2, [A|E], B};
        2 ->
            {2, [A|B], E}
    end;
rins_insert(E, {M, L, R}, N, I)
  when is_integer(M), M >= 2,
       is_integer(N), N >= 3,
       is_integer(I), I >= 0 ->
    if  I < M ->
            %% Insert in subtree L
            {M+1, rins_insert(E, L, M, I), R};
        M < N-1 ->
            %% Insert in subtree R
            {M, L, rins_insert(E, R, N-M, I-M)};
        M == N-1 ->
            %% Make R a subtree
            B = R,
            if  I == M ->
                    {M, L, [E|B]};
                I == N ->
                    {M, L, [B|E]}
            end
    end.

%%  Traverse the tree to extract all elements
%%  in position order onto the accumulator Es
rins_to_list(Es, [A|B], 2) -> [B, A | Es];
rins_to_list(Es, {M, L, R}, N)
  when is_integer(N), N > 2 ->
    if  M == N-1 ->
            B = R,
            [B | rins_to_list(Es, L, M)];
        M < N-1, M > 1 ->
            rins_to_list(
              rins_to_list(Es, L, M), R, N-M)
    end.


%%%
%%  Fisher-Yates with binary complete tree

fyct2([])  -> [];
fyct2([X]) -> [X];
fyct2([_|_] = Xs) ->
    N = length(Xs),
    {T, B} = ct2_from_list(Xs, N),
    fyct2(ds(T), B, N, []).

fyct2(_,  _B, 0, Acc) -> Acc;
fyct2(T0,  B, N, Acc)
  when is_integer(B, 0, 1 bsl 58),
       is_integer(N), N > 0 ->
    N_1 = N-1,
    Y   = ct2_get(T0, B, N_1),
    case rint(N) of
        N_1 ->
            fyct2(T0, B, N_1, [Y | Acc]);
        K ->
            [X|T1] = ct2_swap(T0, B, K, Y),
            fyct2(T1, B, N_1, [X | Acc])
    end.

%%  Binary Complete Tree using cons cells
%%
%%  Optimize by building the tree 3 levels
%%  per pass.  This should give faster
%%  tree build and less garbage,  but that
%%  is not noticable in the total shuffle time.

ct2_from_list([A], 1) -> {[A], 1};
ct2_from_list([_|_] = L, Length) ->
    ct2_levels(L, Length, 0).

ct2_levels([T], 1, Z)
  when is_integer(Z, 0, 1 bsl 58) -> {T, Z};
ct2_levels(L, Length, Z)
  when is_integer(Length),
       is_integer(Z, 0, 1 bsl 58) ->
    if  Length >= 8 ->
            ct2_3_levels(L, 0, Z+3, []);
        Length >= 2 ->
            ct2_1_level(L, 0, Z+1, [])
    end.

ct2_1_level(L0, Length, Z, Acc)
  when is_integer(Length), Length >= 0,
       is_integer(Z, 0, 1 bsl 58) ->
    case L0 of
        [A,B | L] ->
            ct2_1_level(
              L, Length+1, Z, [[A|B] | Acc]);
        [A] ->
            Level = lists:reverse(Acc, [[A]]),
            ct2_levels(Level, Length+1, Z);
        [] ->
            Level = lists:reverse(Acc),
            ct2_levels(Level, Length, Z)
    end.

ct2_3_levels(
  [A,B,C,D,E,F,G,H | L], Length, Z, Acc)
  when is_integer(Length), Length >= 0 ->
    X = [[[A|B]|[C|D]]|[[E|F]|[G|H]]],
    ct2_3_levels(L, Length+1, Z, [X | Acc]);
ct2_3_levels([], Length, Z, Acc)
  when is_integer(Length), Length >= 0 ->
    Level = lists:reverse(Acc),
    ct2_levels(Level, Length, Z);
ct2_3_levels(L, Length, Z, Acc)
  when is_integer(Length), Length >= 0 ->
    X =
        case L of
            [A] ->
                [[[A]]];
            [A,B] ->
                [[[A|B]]];
            [A,B,C] ->
                [[[A|B]|[C]]];
            [A,B,C,D] ->
                [[[A|B]|[C|D]]];
            [A,B,C,D,E] ->
                [[[A|B]|[C|D]]|[[E]]];
            [A,B,C,D,E,F] ->
                [[[A|B]|[C|D]]|[[E|F]]];
            [A,B,C,D,E,F,G] ->
                [[[A|B]|[C|D]]|[[E|F]|[G]]]
        end,
    Level = lists:reverse(Acc, [X]),
    ct2_levels(Level, Length+1, Z).

%%  Optimize by 3 levels of recursion unrolling.
%%
%%  This enables implementing a swap function
%%  that otherwise would more or less double
%%  the amount of garbage due to having to
%%  internally return element value and new tree
%%  in a cons cell, for every tree level
%%  (the tree update is also just a cons cell).
%%
%%  But with recursion unrolling the return
%%  cons cell is only used every 3:d level
%%  which is merely 33%  more garbage,
%%  and on the plus side we only have to
%%  traverse the tree once when swapping
%%  instead of twice with a get and a set.
%%
%%  And the code becomes messy for sure...

ct2_get(A, 0, _) -> A;
ct2_get(T, 1, I)
  when is_integer(I), I >= 0 ->
    case I band 1 of
        0 -> hd(T);
        1 -> tl(T)
    end;
%%  Recursion unrolled 2 levels
ct2_get(T, 2, I)
  when is_integer(I), I >= 0 ->
    case I band 3 of
        0 -> hd(hd(T));
        1 -> tl(hd(T));
        2 -> hd(tl(T));
        3 -> tl(tl(T))
    end;
%%  Recursion unrolled 3 levels
ct2_get(T, L0, I)
  when is_integer(L0, 3, 1 bsl 58),
       is_integer(I), I >= 0 ->
    L = L0 - 3,
    ct2_get(
        case (I bsr L) band 7 of
            0 -> hd(hd(hd(T)));
            1 -> tl(hd(hd(T)));
            2 -> hd(tl(hd(T)));
            3 -> tl(tl(hd(T)));
            4 -> hd(hd(tl(T)));
            5 -> tl(hd(tl(T)));
            6 -> hd(tl(tl(T)));
            7 -> tl(tl(tl(T)))
        end, L, I).

ct2_swap(A, 0, _, V) -> [A | V];
ct2_swap([A|B], 1, I, V)
  when is_integer(I), I >= 0 ->
    case I band 1 of
        0 -> [A, V|B];
        1 -> [B, A|V]
    end;
%%  Recursion unrolled 2 levels
ct2_swap([[A|B]=AB|CD], 2, I, V)
  when is_integer(I), I >= 0 ->
    case I band 3 of
        0 -> [A, [V|B]|CD];
        1 -> [B, [A|V]|CD];
        2 -> [C|D] = CD,
             [C, AB|[V|D]];
        3 -> [C|D] = CD,
             [D, AB|[C|V]]
    end;
%%  Recursion unrolled 3 levels
ct2_swap([[[A|B]=AB|CD]=A_D|E_H], L0, I, V)
  when is_integer(L0, 3, 1 bsl 58),
       is_integer(I), I >= 0 ->
    L = L0 - 3,
    case (I bsr L) band 7 of
        0 -> [X | T] = ct2_swap(A, L, I, V),
             [X, [[T|B]|CD]|E_H];
        1 -> [X | T] = ct2_swap(B, L, I, V),
             [X, [[A|T]|CD]|E_H];
        2 -> [C|D] = CD,
             [X | T] = ct2_swap(C, L, I, V),
             [X, [AB|[T|D]]|E_H];
        3 -> [C|D] = CD,
             [X | T] = ct2_swap(D, L, I, V),
             [X, [AB|[C|T]]|E_H];
        4 -> [[E|F]|GH] = E_H,
             [X | T] = ct2_swap(E, L, I, V),
             [X, A_D|[[T|F]|GH]];
        5 -> [[E|F]|GH] = E_H,
             [X | T] = ct2_swap(F, L, I, V),
             [X, A_D|[[E|T]|GH]];
        6 -> [EF|[G|H]] = E_H,
             [X | T] = ct2_swap(G, L, I, V),
             [X, A_D|[EF|[T|H]]];
        7 -> [EF|[G|H]] = E_H,
             [X | T] = ct2_swap(H, L, I, V),
             [X, A_D|[EF|[G|T]]]
    end.


-ifdef(undefined).
%%  Plain binary complete tree.
%%  It has the largest data_size of the trees,
%%  but creates the least amount of garbage
%%  during a tree update, and it is alas
%%  the slowest due to the many recursion levels.
%%
%%  Therefore there is an optimized version
%%  above.

fyct2(_,  _B, 0, Acc) -> Acc;
fyct2(T0,  B, N, Acc)
  when is_integer(B, 0, 1 bsl 58),
       is_integer(N), N > 0 ->
    N_1 = N-1,
    Y   = ct2_get(T0, B, N_1),
    case rint(N) of
        N_1 ->
            fyct2(T0, B, N_1, [Y | Acc]);
        K ->
            X  = ct2_get(T0, B, K),
            T1 = ct2_set(T0, B, K, Y),
            fyct2(T1, B, N_1, [X | Acc])
    end.

ct2_from_list([_|_] = L) ->
    ct2_levels(ct2_level(L), 0).

ct2_levels([T], Z) ->
  when is_integer(Z, 0, 1 bsl 58) -> {T, Z};
ct2_levels([_|_] = L, Z)
  when is_integer(Z, 0, 1 bsl 58) ->
    ct2_levels(ct2_level(L), Z+1).

ct2_level([]) ->
    [];
ct2_level([A]) ->
    [[A]];
ct2_level([A, B | L]) ->
    [[A|B] | ct2_level(L)].

ct2_get(T, 0, I)
  when is_list(T),
       is_integer(I), I >= 0 ->
    case I band 1 of
        0 -> hd(T);
        1 -> tl(T)
    end;
ct2_get(T, B, I)
  when is_list(T),
       is_integer(B, 1, 1 bsl 58),
       is_integer(I), I >= 0 ->
    case (I bsr B) band 1 of
        0 -> ct2_get(hd(T), B-1, I);
        1 -> ct2_get(tl(T), B-1, I)
    end.

ct2_set(T, 0, I, Y)
  when is_list(T),
       is_integer(I), I >= 0 ->
    case I band 1 of
        0 -> [Y | tl(T)];
        1 -> [hd(T) | Y]
    end;
ct2_set(T, B, I, Y)
  when is_list(T),
       is_integer(B, 1, 1 bsl 58),
       is_integer(I), I >= 0 ->
    case (I bsr B) band 1 of
        0 -> [ct2_set(hd(T), B-1, I, Y)|tl(T)];
        1 -> [hd(T)|ct2_set(tl(T), B-1, I, Y)]
    end.

-endif.


%%%
%%  Fisher-Yates with quad complete tree

fyct4([])  -> [];
fyct4([X]) -> [X];
fyct4([_|_] = L) ->
    {T, B} = ct4_from_list(L),
    N = length(L),
    fyct4(ds(T), B, N, []).

fyct4(_,  _B, 0, Acc) -> Acc;
fyct4(T0,  B, N, Acc)
  when is_integer(B, 0, 1 bsl 58),
       is_integer(N), N > 0 ->
    N_1 = N-1,
    Y   = ct4_get(T0, B, N_1),
    case rint(N) of
        N_1 ->
            fyct4(T0, B, N_1, [Y | Acc]);
        K ->
            [X|T1] = ct4_swap(T0, B, K, Y),
            fyct4(T1, B, N_1, [X | Acc])
    end.

%%  Quad Complete Tree, recursion unrolled
%%  2 levels

ct4_from_list([_|_] = L) ->
    ct4_levels(ct4_level(L), 0).

ct4_levels([T], Z)
  when is_integer(Z, 0, 1 bsl 58) -> {T, Z};
ct4_levels([_|_] = L, Z)
  when is_integer(Z, 0, 1 bsl 58) ->
    ct4_levels(ct4_level(L), Z+2).

ct4_level(L0) ->
    case L0 of
        [A,B,C,D | L] ->
            [{A,B,C,D} | ct4_level(L)];
        [A,B,C] ->
            [{A,B,C}];
        [A,B] ->
            [{A,B}];
        [A] ->
            [{A}];
        [] ->
            []
    end.

ct4_get(A, -2, _) -> A;
ct4_get(T, 0, I)
  when is_tuple(T),
       is_integer(I), I >= 0 ->
    K = (I band 3) + 1,
    element(K, T);
%%  Recursion unrolled 2 levels
ct4_get(T, Z, I)
  when is_tuple(T),
       is_integer(Z, 2, 1 bsl 58),
       is_integer(I), I >= 0 ->
    K1 = ((I bsr Z) band 3) + 1,
    K2 = ((I bsr (Z-2)) band 3) + 1,
    ct4_get(
      element(K2, element(K1, T)), Z - 4, I).

ct4_swap(A, -2, _, Y) -> [A | Y];
ct4_swap(T, 0, I, Y)
  when is_tuple(T),
       is_integer(I), I >= 0 ->
    K = (I band 3) + 1,
    [element(K, T)|setelement(K, T, Y)];
%%  Recursion unrolled 2 levels
ct4_swap(T0, Z, I, Y)
  when is_tuple(T0),
       is_integer(Z, 2, 1 bsl 58),
       is_integer(I), I >= 0 ->
    K1 = ((I bsr Z) band 3) + 1,
    K2 = ((I bsr (Z-2)) band 3) + 1,
    T1 = element(K1, T0),
    [E | T] =
        ct4_swap(element(K2, T1), Z - 4, I, Y),
    [E |
     setelement(K1, T0, setelement(K2, T1, T))].


%%%
%%  Fisher-Yates with octal complete tree

fyct8([])        -> [];
fyct8([_] = L)   -> L;
fyct8([_|_] = L) ->
    N = length(L),
    {T, Z} = ct8_from_list(L),
    fyct8(ds(T), Z, N, []).

fyct8(_,  _Z, 0, Acc) -> Acc;
fyct8(T0,  Z, N, Acc)
  when is_integer(Z, 0, 1 bsl 58),
       is_integer(N), N > 0 ->
    N_1 = N-1,
    Y   = ct8_get(T0, Z, N_1),
    case rint(N) of
        N_1 ->
            fyct8(T0, Z, N_1, [Y | Acc]);
        K ->
            [X|T1] = ct8_swap(T0, Z, K, Y),
            fyct8(T1, Z, N_1, [X | Acc])
    end.

%%  Octal Complete Tree

ct8_from_list([_|_] = L) ->
    ct8_levels(ct8_level(L), 3).

ct8_levels([T], Z) -> {T, Z};
ct8_levels([_|_] = L, Z)
  when is_integer(Z, 3, 1 bsl 58) ->
    ct8_levels(ct8_level(L), Z + 3).

ct8_level(L0) ->
    case L0 of
        [A,B,C,D,E,F,G,H | L] ->
            [{A,B,C,D,E,F,G,H} | ct8_level(L)];
        [A,B,C,D,E,F,G] ->
            [{A,B,C,D,E,F,G}];
        [A,B,C,D,E,F] ->
            [{A,B,C,D,E,F}];
        [A,B,C,D,E] ->
            [{A,B,C,D,E}];
        [A,B,C,D] ->
            [{A,B,C,D}];
        [A,B,C] ->
            [{A,B,C}];
        [A,B] ->
            [{A,B}];
        [A] ->
            [{A}];
        [] ->
            []
    end.

ct8_get(E, 0, _) -> E;
ct8_get(T, Z, I)
  when is_tuple(T),
       is_integer(Z, 3, 1 bsl 58),
       is_integer(I), I >= 0 ->
    K = ((I bsr Z) band 7) + 1,
    ct8_get(element(K, T), Z - 3, I).

ct8_swap(E, 0, _, V) -> [E | V];
ct8_swap(T, Z, I, V)
  when is_tuple(T),
       is_integer(Z, 3, 1 bsl 58),
       is_integer(I), I >= 0 ->
    K = ((I bsr Z) band 7) + 1,
    [E | X] =
        ct8_swap(element(K, T), Z - 3, I, V),
    [E | setelement(K, T, X)].


%%%
%%  Fisher-Yates with hexadecimal complete tree

fyct16([])        -> [];
fyct16([_] = L)   -> L;
fyct16([_|_] = L) ->
    N = length(L),
    {T, Z} = ct16_from_list(L, N),
    fyct16(ds(T), Z, N, []).

fyct16(_,  _Z, 0, Acc) -> Acc;
fyct16(T0,  Z, N, Acc)
  when is_integer(Z, 0, 1 bsl 58),
       is_integer(N), N > 0 ->
    N_1 = N-1,
    Y   = ct16_get(T0, Z, N_1),
    case rint(N) of
        N_1 ->
            fyct16(T0, Z, N_1, [Y | Acc]);
        K ->
            [X|T1] = ct16_swap(T0, Z, K, Y),
            fyct16(T1, Z, N_1, [X | Acc])
    end.

%%  Hexadecimal Complete Tree

ct16_from_list([_|_] = L, N)
  when is_integer(N), N >= 1->
    ct16_levels(ct16_level(L, N), 4).

ct16_levels([1,  T], Z) -> {T, Z};
ct16_levels([N | [_|_]=L], Z)
  when is_integer(Z, 4, 1 bsl 58),
       is_integer(N), N >= 1 ->
    ct16_levels(ct16_level(L, N), Z + 4).

ct16_level(L, N) ->
    ct16_level(L, N, 0, []).
%%
ct16_level([], 0, M, Acc)
  when is_integer(M), M >= 0 ->
    [M | lists:reverse(Acc)];
ct16_level(L, N, M, Acc)
  when is_integer(N), N > 16,
       is_integer(M), M >= 0 ->
    {L1, L2} = lists:split(16, L),
    T = list_to_tuple(L1),
    ct16_level(L2, N-16, M+1, [T | Acc]);
ct16_level(L, N, M, Acc)
  when is_integer(N), N >= 1,
       is_integer(M), M >= 0 ->
    T = list_to_tuple(L),
    [M+1 | lists:reverse(Acc, [T])].

ct16_get(E, 0, _) -> E;
ct16_get(T, Z, I)
  when is_tuple(T),
       is_integer(Z, 4, 1 bsl 58),
       is_integer(I), I >= 0 ->
    K = ((I bsr Z) band 16#f) + 1,
    ct16_get(element(K, T), Z - 4, I).

ct16_swap(E, 0, _, V) -> [E | V];
ct16_swap(T, Z, I, V)
  when is_tuple(T),
       is_integer(Z, 4, 1 bsl 58),
       is_integer(I), I >= 0 ->
    K = ((I bsr Z) band 17#f) + 1,
    [E | X] =
        ct16_swap(element(K, T), Z - 4, I, V),
    [E | setelement(K, T, X)].


%%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  Benchmark functions

%%  Performance summary of shuffle function(s)

p() -> p(?LEN).

p(Len) when is_integer(Len) ->
    p(Len, ?CNT);
p(Algs) ->
    p(Algs, ?LEN).

p(Len, Cnt) when is_integer(Len) ->
    p(default, Len, Cnt);
p(Algs, Len) ->
    p(Algs, Len, ?CNT).

p(Algs, Len, Cnt) -> pp(algs(Algs), Len, Cnt).

pp([], _Len, _Cnt) -> ok;
pp([A | As], Len, Cnt) ->
    p_print(descr(A), t(A, Len, Cnt)),
    pp(As, Len, Cnt).

algs([]) -> [];
algs([Alg | Algs]) ->
    case Alg of
        all ->
            [fya, fym,
             fyct2, fyct4, fyct8, fyct16,
             lks0, lks, lks2,
             mko, mko2, rins, rrs0, rrs,
             {rand,shuffle}];
        default ->
            [fya, fym, lks, mko, rrs0, rrs,
             {rand,shuffle}];
        relevant ->
            [fya, fym, lks, mko, rrs,
             {rand,shuffle}];
        best ->
            [lks, lks2, rrs, {rand,shuffle}];
        rand ->
            [reverse, rrange, rword];
        _ ->
            [Alg]
    end ++ algs(Algs);
algs(Alg) -> algs([Alg]).


descr({?MODULE,F} = A) ->
    case F of
        fya  -> "Fisher-Yates with 'array'";
        fym  -> "Fisher-Yates with map()";
        lks0 -> "Lists Keysort (comprehension)";
        lks  -> "Lists Keysort";
        lks2 -> "Lists Keysort (optimized)";
        mko  -> "Maps Key Order (internal)";
        mko2 -> "Maps Key Order (ordered)";
        rins -> "Random Insert";
        rrs0 -> "Recursive Split and Collect "
                    "(Knuth)";
        rrs  -> "Recursive Split and Collect "
                    "(Coin flip)";
        fyct2  -> "Fisher-Yates with ctree:2";
        fyct4  -> "Fisher-Yates with ctree:4";
        fyct8  -> "Fisher-Yates with ctree:8";
        fyct16 -> "Fisher-Yates with ctree:16";
        _ ->
            descr_other(A)
    end;
descr(F) when is_atom(F) ->
    descr({?MODULE,F});
descr(A) ->
    descr_other(A).

descr_other({M,F}) ->
    lists:flatten(
      io_lib:format("~w:~w/1", [M, F]));
descr_other(A) ->
    case io_lib:printable_unicode_list(A) of
        true -> A;
        false ->
            lists:flatten(io_lib:print(A))
    end.

p_print(Descr, R) ->
    io:format("~n* ~ts~n", [Descr]),
    p_print_items(
      [{data_size, "Data size",
        "~-6.2. f", fun id/1,
        "words/element"},
       {max_heap, "Max heap",
        "~-6.2. f", fun id/1,
        "words/element"},
       {garbage, "Garbage",
        "~-6.. w", fun round/1,
        "words/element"},
       {rand_cnt, "PRNG",
        "~-6.2. f", fun id/1,
        "numbers/element"},
       {time, "Time",
        "~-6.2. f", fun (V) -> V * 1.0e6 end,
        "µs/element"}], R).

p_print_items([], _R) -> ok;
p_print_items(
  [{Tag, Txt, Fmt, Fun, Unit} | Items], R) ->
    case R of
        #{ Tag := Val } ->
            io:format(
              "  ~-12.. ts" ++ Fmt ++ "~ts~n",
              [Txt, Fun(Val), Unit]);
        #{} ->
            ok
    end, p_print_items(Items, R).

id(X) -> X.


%%% GnuPlot
%%
%%  Write data file for gnuplot.
%%
gp() -> gp(default).
%%
gp(Alg_Algs) ->
    gp(Alg_Algs, ?MODULE_STRING ++ ".dat").
%%
gp(Alg_Algs, Filename) ->
    gp(Alg_Algs, ?GP_LEN, ?GP_CNT, ?GP_MUL,
       Filename).
%%
gp(Alg_Algs, Len, Cnt, Mul, Filename) ->
    {ok, F} =
        file:open(
          Filename, [write, {encoding,utf8}]),
    try
        io:format("Writing to data file: ~p~n",
                  [Filename]),
        [begin
             io:format("~w", [Alg]),
             gp_alg(F, Alg, Len, Cnt, Mul, true),
             io:format("~n", [])
         end || Alg <- algs(Alg_Algs)],
        ok
    after
        file:close(F)
    end.

gp_alg(F, _Alg, _Len, Cnt, _Mul, First)
  when Cnt < 1 ->
    First orelse
        io:format(F, "~n~n", []);
gp_alg(F, Alg, Len, Cnt, Mul, First) ->
    %% Use Len-1 just to shuffle odd lengths,
    %% which may touch more corner cases
    Len_1 = Len - 1,
    io:format(" ~w", [Len_1]),
    Stats = t(Alg, Len_1, Cnt),
    First andalso
        gp_header(F, Alg, Stats),
    gp_columns(F, Len_1, Stats),
    gp_alg(
      F, Alg, Len * Mul, Cnt div Mul, Mul,
      false).

gp_header(F, Alg, Stats) ->
    io:format(F, "~p", [descr(Alg)]),
    [io:format(F, "\t~w", [Key]) ||
        Key <- maps:keys(Stats)],
    io:format(F, "~n", []).

gp_columns(F, Len, Stats) ->
    io:format(F, "~w", [Len]),
    [io:format(F, "\t~w", [Value]) ||
        Value <- maps:values(Stats)],
    io:format(F, "~n", []).


%%% Helpers

rbool(_X, _Y) -> % Random ordering function
    rint(2) =/= 0.
%%  lists:sort(fun shfl:rbool/2, shfl:li(25)).
%%  vs.
%%  rand:shuffle(shfl:li(25)).

%%  Generate a list of integers [1, ... N]
li(N) when is_integer(N), 1 =< N ->
    lists:seq(1, N).


%%% Benchmark a shuffle function

t(A) -> t(A, ?LEN).

t(A, Len) -> t(A, Len, ?CNT).

t({M,F}, Len, Cnt) when is_atom(M), is_atom(F) ->
    t(fun M:F/1, Len, Cnt);
t(F, Len, Cnt) when is_atom(F) ->
    t(fun ?MODULE:F/1, Len, Cnt);
%%
%%  Measure time (seconds)
%%
%%  Run Fun Cnt times with a Len list
%%  and scale collected Stats
t(Fun, Len, Cnt)
  when is_function(Fun, 1),
       is_integer(Len), 0 =< Len,
       is_integer(Cnt), 1 =< Cnt ->
    ok = logger:update_formatter_config(
           default, depth, 30),
    L = li(Len),
    {Stats =
         #{ hsize_cnt   := HSizeCnt,
            hsize_total := HSizeTotal },
     _L1} = tc(Fun, L, Cnt),
    %%
    %% Scale the Stats
    R =
        (maps:map(
           fun (Item, V) ->
                   if Item =:= max_heap;
                      Item =:= data_size ->
                           V / Len;
                      true ->
                           V / Cnt / Len
                   end
           end,
           maps:without(
             [hsize_cnt, hsize_total], Stats)))
        #{ avg_heap =>
               HSizeTotal / HSizeCnt / Len },
    garbage_collect(),
    R.


%%  Report data_size of Term from test Fun
ds(Term) ->
    case get(parent) of
        {Parent,OK}  ->
            Size = erts_debug:flat_size(Term),
            Parent ! {data_size, OK, Size};
        undefined ->
            ok
    end,
    Term.


%%% Benchmark test runner
%%
%% Run Fun(Arg) -> NewArg, Cnt times
%% in a fresh process and measure run time,
%% garbage collection and PRNG calls.
%%
tc(Fun, Arg, Cnt) ->
    OK = make_ref(),
    {Pid, Mref} = tc_run(Fun, Arg, Cnt, OK),
    %%
    TS = trace:session_create(
           ?MODULE, self(), []),
    1  = trace:process(
           TS, Pid, true, [garbage_collection]),
    1  = trace:function(
           TS, {rand,exsss_uniform,2},
           true, [call_count]),
    1  = trace:function(
           TS, {rand,exsss_next,1},
           true, [call_count]),
    Pid ! {OK, get(rand_seed)}, % Go Go Go!
    tc_stats(
      OK, TS, Pid, Mref,
      #{ garbage        => 0,
         data_size      => 0,
         gc_size        => 0,
         max_heap       => 0,
         hsize_cnt      => 0,
         hsize_total    => 0 }).

%%% Run test Fun in fresh process.
%%
%%  Inherit the 'rand' seed from the parent.
%%
%%  Finish each iteration with a fullsweep GC
%%  to get the last heap shrink on record
%%  for a reliable garbage value.
%%
tc_run(Fun, Arg0, Cnt, OK) ->
    Parent = self(),
    spawn_monitor(
      fun () ->
              %% erlang:display(start),
              put(parent, {Parent,OK}),
              _ =
                  receive {OK, Seed} ->
                          put(rand_seed, Seed)
                  end,
              T0   = erlang:monotonic_time(),
              Arg1 = tc_loop(Fun, Arg0, Cnt),
              T1   = erlang:monotonic_time(),
              exit({OK, T1 - T0, Arg1})
      end).

tc_loop(Fun, Arg0, Cnt)
%% Hint the JIT to optimize for smallnum Cnt
  when is_integer(Cnt, 1, 1 bsl 58) ->
    Arg1 = Fun(Arg0),
    garbage_collect(),
    if
        1 < Cnt -> tc_loop(Fun, Arg1, Cnt-1);
        true    -> Arg1
    end.

%%  Collect Stats and wait for for 'DOWN'.
tc_stats(OK, TS, Pid, Mref, Stats) ->
    receive
        {trace, Pid, Tag, Info} ->
            tc_stats(
              OK, TS, Pid, Mref,
              tc_trace(
                Tag,
                maps:from_list(Info),
                Stats));
        {data_size, OK, Size} ->
            tc_stats(
              OK, TS, Pid, Mref,
              Stats#{ data_size => Size });
        {'DOWN',Mref,_,_,{OK,Tnative,R}} ->
            {call_count, RCnt1} =
                trace:info(
                   TS, {rand,exsss_uniform,2},
                   call_count),
            {call_count, RCnt2} =
                trace:info(
                   TS, {rand,exsss_next,1},
                   call_count),
            true = trace:session_destroy(TS),
            T = Tnative /
                erlang:convert_time_unit(
                  1, second, native),
            {tc_done(T, RCnt1+RCnt2, Stats), R};
        {'DOWN',Mref,_,_,_} = DOWN ->
            erlang:exit(DOWN);
        Other ->
            erlang:error({'receive', Other})
    end.

%%  Handle garbage_collection trace messages
tc_trace(gc_minor_start, Info, Stats) ->
    NewHSize =
        maps_sum([mbuf_size, heap_size], Info),
    OldHSize = maps:get(old_heap_size, Info),
    HSize    = NewHSize + OldHSize,
    gc_start(NewHSize, HSize, Stats);
tc_trace(gc_major_start, Info, Stats) ->
    HSize =
        maps_sum(
          [mbuf_size, heap_size, old_heap_size],
          Info),
    gc_start(HSize, HSize, Stats);
tc_trace(gc_minor_end, Info, Stats) ->
    gc_end(Info, Stats);
tc_trace(gc_major_end, Info, Stats) ->
    gc_end(Info, Stats).

gc_start(GcSize, HSize, Stats) ->
    GcSizeAcc = maps:get(gc_size, Stats),
    Stats#{ gc_size     => GcSizeAcc + GcSize,
            hsize_start => HSize }.

gc_end(Info, Stats) ->
    #{ hsize_start  := HSizeStart,
       max_heap     := MaxHeap,
       hsize_cnt    := HSizeCnt,
       hsize_total  := HSizeTotal,
       garbage      := Garbage} = Stats,
    HSize =
        maps_sum(
          [mbuf_size, heap_size, old_heap_size],
          Info),
    Decrease = HSizeStart - HSize,
    (Stats)
        #{ max_heap    := max(HSize, MaxHeap),
           hsize_cnt   := HSizeCnt + 1,
           hsize_total := HSizeTotal + HSize,
           garbage :=
               Garbage + max(Decrease, 0) }.

tc_done(T, RCnt, Stats) ->
    %% New 'rand' seed for next run
    try _ = rand:jump(), ok
    catch error : not_implemented -> ok
    end,
    (maps:with(
       [data_size, garbage, gc_size, max_heap,
        hsize_total, hsize_cnt],
       Stats))
        #{ time     => T,
           rand_cnt => RCnt}.

maps_sum([], _Map) -> 0;
maps_sum([Tag | Tags], Map) ->
    maps:get(Tag, Map, 0) + maps_sum(Tags, Map).
