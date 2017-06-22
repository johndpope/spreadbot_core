%%%-------------------------------------------------------------------
%% @doc spreadbot_core public API
%% @end
%%%-------------------------------------------------------------------

-module(spreadbot_core_app).

-behaviour(application).

-export([
    update/2, update/3,
    subscribe/3,
    get_iteration_and_opaque/1
]).

%% Application callbacks
-export([start/2, stop/1]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-type iteration() :: integer().
-type opaque() :: any().
-type path() :: [binary()].
-export_type([iteration/0, opaque/0, path/0]).
%%====================================================================
%% API
%%====================================================================

%% Updates the tree, warns the subscribers.
%% WARNING: susbscribers may receive update notifications out of order for performance sake
%% it is their responsibility to make sure the event is not outdated already,
%% and make sure they use margin when asking for a timestamp after deconnexion

-spec update(path(), opaque()) -> {too_late, opaque()} | {iteration(), [{[any()], integer()}], any() | error}.
update(PathAsList, Opaque) ->
    update(PathAsList, Opaque, false).

%% @todo: instead of timestamp, use a version number, so we can make sure it is monotonically increasing
-spec update(path(), opaque(), boolean()) -> {too_late, opaque()} | {iteration(), [{[any()], integer()}], opaque() | error}.
update(PathAsList, Opaque, FailIfExists) ->
    case spreadbot_core_data:update(PathAsList, Opaque, FailIfExists) of
        {_Iteration, drop, OldOpaque} ->
            {too_late, OldOpaque};
        {Iteration, AllPaths, OldOpaque} ->
            case FailIfExists of
                true when OldOpaque =/= error ->
                    {Iteration, [], OldOpaque};
                _ ->
                    {Iteration, [spreadbot_core_subs:warn_subscribers(Path, {update, PathAsList, Iteration, Opaque}) || Path <- AllPaths], OldOpaque}
            end
    end.

%% @todo: add ability to subscribe to that particular path and not his children
-spec subscribe(path(), iteration(), pid()) -> [{path(), iteration(), opaque()}].
subscribe(PathAsList, Iteration, Pid) ->
    %% Add the subscriber to the list BEFORE browsing so we don't miss any event
    spreadbot_core_subs:add_subscriber(PathAsList, Pid),
    UpdatedSelf = case spreadbot_core_data:get_iteration_and_opaque(PathAsList) of
        {LastIteration, Opaque} ->
            if
                LastIteration > Iteration ->
                    [{PathAsList, LastIteration, Opaque}];
                true ->
                    []
            end;
        error ->
            []
    end,
    %% Browse current children state
    UpdatedChildren = spreadbot_core_data:browse(PathAsList, Iteration),
    UpdatedSelf ++ UpdatedChildren.

-spec get_iteration_and_opaque(path()) -> {iteration(), opaque()} | error.
get_iteration_and_opaque(PathAsList) ->
    spreadbot_core_data:get_iteration_and_opaque(PathAsList).

start(_StartType, _StartArgs) ->
    spreadbot_core_sup:start_link().

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================
-ifdef(TEST).
spreadbot_core_subs_test() ->
    application:start(spreadbot_core),
    Pid = spawn(fun() -> timer:sleep(200) end),
    spreadbot_core_subs:add_subscriber([<<"toto">>], Pid),
    ?assertEqual(lists:sort(ets:tab2list(spreadbot_core_subs_bag)), [{Pid,[<<"toto">>]},{[<<"toto">>],Pid}]),
    timer:sleep(100),
    {It, _, error} = update([<<"toto">>], {1, test1}, false),
    timer:sleep(120),
    ?assertEqual(ets:tab2list(spreadbot_core_subs_bag), []),
    ?assertEqual({It, {1, test1}}, get_iteration_and_opaque([<<"toto">>])),
    spreadbot_core_subs ! {gc},
    spreadbot_core_subs ! any,
    gen_server:cast(spreadbot_core_subs, any),
    gen_server:call(spreadbot_core_subs, any),
    application:stop(spreadbot_core).


spreadbot_core_data_test() ->
    application:start(spreadbot_core),
    {It, _,  error} = update(["toto", "titi", "tata", "item1"], {1, test1}),
    update(["toto", "titi", "tata", "item2"], {2, test2}, false),
    update(["toto", "titi", "tata", "item2"], {3, test3}, false),
    update(["toto", "titi", "tata", "item3"], {2, test4}, false),
    update(["toti"], {4, test5}),
    ?assertEqual(
        [{["toto","titi","tata","item1"], It, {1, test1}},
                  {["toto","titi","tata","item2"], It+2, {3, test3}},
                  {["toto","titi","tata","item3"], It+3, {2, test4}}],
        lists:sort(subscribe(["toto", "titi", "tata"], 0, self()))                  
    ),
    ?assertEqual(
        [{["toto","titi","tata","item2"], It+2, {3, test3}}],
        lists:sort(subscribe(["toto", "titi", "tata", "item2"], 0, self()))
    ),
    ?assertEqual(
        [],
        lists:sort(subscribe(["toto", "titi", "tata", "item2"], It+2, self()))
    ),
    ?assertEqual(
        update(["toto", "titi", "tata", "item2"], {2, test5}, false),
        {too_late,{3, test3}}
    ),
    update(["toto", "titi", "tata", "item2"], {4, test6}, false),
    receive
        {update, Path, NewIt, Opaque} ->
            ?assertEqual(Path, ["toto", "titi", "tata", "item2"]),
            ?assertEqual(NewIt, It+6),
            ?assertEqual(Opaque, {4, test6})
    after 0 ->
        throw(no_message_received)
    end,
    Subs = subscribe([], 0, self()),
    ?assertEqual(
        lists:sort(Subs),
        [{["toti"], It+4, {4, test5}},
                  {["toto", "titi", "tata", "item1"], It, {1, test1}},
                  {["toto", "titi", "tata", "item2"], It+6, {4, test6}},
                  {["toto", "titi", "tata", "item3"], It+3, {2, test4}}]),

    {It2, _, error} = update(["toto", "titi"], {4, test5}, true),
    ?assertEqual(It+7, It2),
    spreadbot_core_data ! {gc},
    spreadbot_core_data ! any,
    gen_server:cast(spreadbot_core_data, any),
    gen_server:call(spreadbot_core_data, any),

    application:stop(spreadbot_core).
    
-endif.
