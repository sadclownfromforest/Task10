%%%-------------------------------------------------------------------
%% @doc code_lock top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(code_lock_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).


init([]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 0,
        period => 1
    },
    ChildSpecs = [#{id => code_lock,
		    start => {code_lock, start_link, [[1,1,1], "L"]},
		    restart => permanent,
		    shutdown => 5000,
		    type => worker,
		    modules => [code_lock]}],

    {ok, {SupFlags, ChildSpecs}}.

