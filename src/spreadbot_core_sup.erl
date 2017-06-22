%%%-------------------------------------------------------------------
%% @doc spreadbot_core top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(spreadbot_core_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

init([]) ->
    spreadbot_core_subs:init_from_sup(),
    Subs = {spreadbot_core_subs, {spreadbot_core_subs, start_link, []}, permanent, 5000, worker, [spreadbot_core_subs]},
    spreadbot_core_data:init_from_sup(),
    Data = {spreadbot_core_data, {spreadbot_core_data, start_link, []}, permanent, 5000, worker, [spreadbot_core_data]},
    %% If subs dies, we will just loose all monitors
    %% @todo: when spreadbot_core_subs starts, replace all monitors
    %% If data dies, we loose updates in the process mailbox
    {ok, { {one_for_all, 1, 5}, [
        Subs,
        Data
    ]} }.
%%====================================================================
%% Internal functions
%%====================================================================
