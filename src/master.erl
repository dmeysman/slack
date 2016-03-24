%% @doc Process which manages users, their receivers, and channels.
%% @version 0.1.0
%% @author Dylan Meysmans <dmeysman@vub.ac.be>
%%   [http://student.vub.ac.be/~dmeysman]
%% @copyright 2016 Dylan Meysmans
-module(master).

-include_lib("eunit/include/eunit.hrl").

-export([initialize/0, initialize_with/3, master_actor/3]).

-spec initialize() -> pid().
%% @doc Creates a new master process with no users, no receivers, and no channels.
initialize() ->
  initialize_with(dict:new(), gb_trees:empty(), dict:new()).

-spec initialize_with(Subscriptions :: dict:dict(string(), {user, string(), sets:set(string())}),
                      Receivers     :: gb_trees:tree(string(), pid()),
                      Channels      :: dict:dict(string(), pid())) -> pid().
%% @doc Creates a new master process with `Subscriptions', `Receivers',
%%   and `Channels'.
initialize_with(Subscriptions, Receivers, Channels) ->
  Master = spawn_link(?MODULE, master_actor, [Subscriptions, Receivers, Channels]),
  catch unregister(master_actor),
  register(master_actor, Master),
  Master.

-spec master_actor(Subscriptions :: dict:dict(string(), {user, string(), sets:set(string())}),
                   Receivers     :: gb_trees:tree(string(), pid()),
                   Channels      :: dict:dict(string(), pid())) -> any().
%% @doc Represents a master process.
master_actor(Subscriptions, Receivers, Channels) ->
  receive
    {Sender, register_user, UserName} ->
      % We first create a new user subscribed to no channels.
      NewSubscriptions = dict:store(UserName, {user, UserName, sets:new()}, Subscriptions),
      % We then tell the user to continue to send messages to us, as he is
      %   not logged in at this point.
      Sender ! {self(), user_registered},
      % Finally, we proceed with the new state.
      master_actor(NewSubscriptions, Receivers, Channels);

    {Sender, log_in, UserName} ->
      % We first create a receiver and notify all channels the user subscribes to.
      Receiver = log_in(Sender, dict:fetch(UserName, Subscriptions), Channels),
      % We then tell the user to send all future messages to its receiver
      %   instead of us.
      Sender ! {Receiver, logged_in},
      % Finally, we register the receiver to the user's name in our state and proceed.
      master_actor(Subscriptions, gb_trees:insert(UserName, Receiver, Receivers), Channels);

    {Sender, log_out, UserName} ->
      % We first notify all channels the user subscribes to and dispose of the receiver.
      log_out(Sender, dict:fetch(UserName, Subscriptions), Channels),
      Sender ! {self(), logged_out},
      master_actor(Subscriptions, gb_trees:delete(UserName, Receivers), Channels);

    {Sender, join_channel, UserName, ChannelName} ->
      NewSubscriptions = dict:update(UserName, subscribe(ChannelName), Subscriptions),
      NewChannels = find_or_create_channel(gb_trees:values(Receivers), ChannelName, Channels),
      dict:fetch(ChannelName, NewChannels) ! {self(), join_channel, {user, UserName, Sender}},
      Sender ! {self(), channel_joined},
      master_actor(NewSubscriptions, Receivers, NewChannels);

    {Sender, get_channel_history, ChannelName} ->
      dict:fetch(ChannelName, Channels) ! {Sender, get_channel_history},
      master_actor(Subscriptions, Receivers, Channels)
  end.

-spec log_in(UserPid  :: pid(),
             User     :: {user, string(), sets:set(string())},
             Channels :: dict:dict(string(), pid())) -> pid().
log_in(UserPid, {user, SubscriberName, Subscriptions}, Channels) ->
  % We first create a receiver for the user.
  Receiver = receiver:initialize_with(Channels),
  % We then notify all channels the user subscribes to that he wishes to join them.
  _ = [dict:fetch(Subscription, Channels) ! {self(), join_channel, {user, SubscriberName, UserPid}} || Subscription <- sets:to_list(Subscriptions)],
  % Finally, we return the process identifier of the newly created receiver.
  Receiver.

log_out(UserPid, {user, SubscriberName, Subscriptions}, Channels) ->
  % We notify all channels the user subscribes to that he wishes to leave them.
  _ = [dict:fetch(Subscription, Channels) ! {self(), leave_channel, {user, SubscriberName, UserPid}} || Subscription <- sets:to_list(Subscriptions)].

find_or_create_channel(ReceiverPids, ChannelName, Channels) ->
  case dict:find(ChannelName, Channels) of
    {ok, _} ->
      Channels;
    error ->
      NewChannels = dict:store(ChannelName, channel:initialize(), Channels),
      _ = [ReceiverPid ! {self(), updated_channels, NewChannels} || ReceiverPid <- ReceiverPids],
      NewChannels
  end.

-spec subscribe(string()) -> fun(({user, string(), sets:set(string())}) -> {user, string(), sets:set(string())}).
%% @doc Generates a function which subscribes a user to `ChannelName'.
subscribe(ChannelName) ->
  fun({user, UserName, Subscriptions}) ->
    {user, UserName, sets:add_element(ChannelName, Subscriptions)}
  end.
