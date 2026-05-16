-module(code_lock).
-behaviour(gen_statem).
-define(NAME, code_lock_4).


-export([start_link/2, stop/0]).
-export([button/1, set_lock_button/1, change_code/1]).
-export([init/1, callback_mode/0, terminate/3]).
-export([handle_event/4]).

-include_lib("eunit/include/eunit.hrl").



start_link(Code, LockButton) ->
    gen_statem:start_link({local, ?NAME}, ?MODULE, {Code, LockButton}, []).

stop() ->
    gen_statem:stop(?NAME).

button(Button) ->
    gen_statem:cast(?NAME, {button, Button}).

set_lock_button(LockButton) ->
    gen_statem:call(?NAME, {set_lock_button, LockButton}).

change_code(NewCode) ->
    gen_statem:call(?NAME, {change_code, NewCode}).

init({Code, LockButton}) ->
    process_flag(trap_exit, true),
    Data = #{code => Code, length => length(Code), buttons => [], wrong_attempts => 0},
    {ok, {locked, LockButton}, Data}.

callback_mode() ->
    [handle_event_function, state_enter].



handle_event(enter, _OldState, {locked, _}, Data) ->
    do_lock(),
    {keep_state, Data#{buttons := []}};

handle_event(state_timeout, button, {locked, _}, Data) ->
    {keep_state, Data#{buttons := [], wrong_attempts := 0}};

handle_event(
    cast, {button, Button}, {locked, LockButton},
    #{code := Code, length := Length, buttons := Buttons, wrong_attempts := Attempts} = Data) ->

    NewButtons = if
                    length(Buttons) < Length -> Buttons;
                    true -> tl(Buttons)
                 end ++ [Button],

    if
        NewButtons =:= Code -> % Correct
            {next_state, {open, LockButton}, Data#{buttons := [], wrong_attempts := 0}};

        length(NewButtons) =:= Length -> %Incorrect
            NewAttempts = Attempts + 1,
            print_incorrect(),
            if
                NewAttempts >= 3 ->
                    {next_state, {suspended, LockButton}, Data#{buttons := [], wrong_attempts := 0}};
                true ->
                    {keep_state, Data#{buttons := [], wrong_attempts := NewAttempts},
                     [{state_timeout, 30_000, button}]}
            end;
        true -> % Incomplete
            {keep_state, Data#{buttons := NewButtons}, [{state_timeout, 30_000, button}]}
    end;




handle_event(enter, _OldState, {suspended, _}, _Data) ->
    io:format("Suspended~n", []),
    {keep_state_and_data, [{state_timeout, 10_000, unsuspend}]};

handle_event(state_timeout, unsuspend, {suspended, LockButton}, Data) ->
    io:format("Unsuspended~n", []),
    {next_state, {locked, LockButton}, Data};

handle_event(cast, {button, _}, {suspended, _}, _Data) ->
    {keep_state_and_data};



handle_event(enter, _OldState, {open, _}, _Data) ->
    do_unlock(),
    {keep_state_and_data, [{state_timeout, 10_000, lock}]};

handle_event(state_timeout, lock, {open, LockButton}, Data) ->
    {next_state, {locked, LockButton}, Data};

handle_event(cast, {button, LockButton}, {open, LockButton}, Data) ->
    {next_state, {locked, LockButton}, Data};

handle_event(cast, {button, _}, {open, _}, _Data) ->
    {keep_state_and_data, [postpone]};



handle_event({call, From}, {change_code, NewCode}, {open, _}, Data) ->
    io:format("Code was changed.~n", []),
    NewData = Data#{code := NewCode, length := length(NewCode)},
    {keep_state, NewData, [{reply, From, ok}]};

handle_event({call, From}, {change_code, _}, {StateName, _}, _Data) ->
    {keep_state_and_data, [{reply, From, {error, {not_open, StateName}}}]};



handle_event({call, From}, {set_lock_button, NewLockButton}, {StateName, OldLockButton}, Data) ->
    {next_state, {StateName, NewLockButton}, Data, [{reply, From, OldLockButton}]}.


do_lock() -> io:format("Locked~n", []).
do_unlock() -> io:format("Open~n", []).
print_incorrect() -> io:format("Incorrect Password~n", []).

terminate(_Reason, State, _Data) ->
    (State =/= locked) andalso do_lock(),
    ok.





code_lock_test_() ->
    {foreach,
     fun() -> {ok, _} = start_link([1, 2, 3], "L") end,
     fun(_) -> stop() end,
     [
      fun test_open_lock/0,
      fun test_good_change_code/0,
      fun test_bad_change_code/0,
      fun test_suspended/0
     ]}.

test_open_lock() ->
    button(1),
    button(2),
    button(3),
    {StateName, _} = sys:get_state(?NAME),
    ?assertMatch({open, _}, StateName).

test_good_change_code() ->
    button(1),
    button(2),
    button(3),
    Result = change_code([17, 2]),
    ?assertEqual(ok, Result),
    button("L"),
    button(17), button(2),
    {StateName, _} = sys:get_state(?NAME),
    ?assertMatch({open, _}, StateName).

test_bad_change_code() ->
    Result = change_code([6, 8]),
    ?assertEqual({error, {not_open, locked}}, Result).

test_suspended() ->
    button(1),
    button(1),
    button(1),
    {State1, _} = sys:get_state(?NAME),
    ?assertMatch({locked, _}, State1),
    button(1),
    button(1),
    button(1),
    {State1, _} = sys:get_state(?NAME),
    ?assertMatch({locked, _}, State1),
    button(1),
    button(1),
    button(1),
    {State2, _} = sys:get_state(?NAME),
    ?assertMatch({suspended, _}, State2).
