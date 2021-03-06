%% @doc Process which manages users, their receivers, and channels.
%% @version 0.1.0
%% @author Dylan Meysmans <dmeysman@vub.ac.be>
%%   [http://student.vub.ac.be/~dmeysman]
%% @copyright 2016 Dylan Meysmans
-module(master).

-export([initialize/0, initialize_with/2, master_actor/2]).

-spec initialize() -> pid().
%% @doc Creates a new master process with no users and no channels.
initialize() ->
  initialize_with(dict:new(), dict:new()).

-spec initialize_with(Subscriptions :: dict:dict(string(), {user, string(), sets:set(string())}),
                      Channels      :: dict:dict(string(), pid())) -> pid().
%% @doc Creates a new master process with `Subscriptions', `Receivers',
%%   and `Channels'.
initialize_with(Subscriptions, Channels) ->
  Master = spawn_link(?MODULE, master_actor, [Subscriptions, Channels]),
  catch unregister(master_actor),
  register(master_actor, Master),
  Master.

-spec master_actor(Subscriptions :: dict:dict(string(), {user, string(), sets:set(string())}),
                   Channels      :: dict:dict(string(), pid())) -> no_return().
%% @doc Represents a master process.
master_actor(Subscriptions, Channels) ->
  receive
    {Sender, register_user, UserName} ->
      % We first create a new user subscribed to no channels.
      NewSubscriptions = dict:store(UserName, {user, UserName, sets:new()}, Subscriptions),
      % We then tell the user to continue to send messages to us, as he is
      %   not logged in at this point.
      Sender ! {self(), user_registered},
      % Finally, we proceed with the new state.
      master_actor(NewSubscriptions, Channels);

    {Sender, log_in, UserName} ->
      % We first create a receiver for the user and tell him to send all future
      %   messages to his receiver instead of us.
      Sender ! {receiver:initialize_with(Sender, dict:fetch(UserName, Subscriptions), Channels), logged_in},
      % Finally, we proceed.
      master_actor(Subscriptions, Channels);

    {Sender, log_out, UserName} ->
      % We first notify all channels the user subscribes to and dispose of the receiver.
      log_out(Sender, dict:fetch(UserName, Subscriptions), Channels),
      % We then notify the sender that we successfully logged the user out.
      Sender ! {self(), logged_out},
      % Finally, we proceed.
      master_actor(Subscriptions, Channels);

    {Sender, Receiver, join_channel, UserName, ChannelName} ->
      % We first subscribe the user to the channel.
      NewSubscriptions = dict:update(UserName, subscribe(ChannelName), Subscriptions),
      % We then spawn a new channel process if the channel does not exist yet.
      ChannelPid = find_or_create_channel(ChannelName, Channels),
      % The user's receiver needs to be aware of the new channel's information.
      Receiver ! {self(), new_channel, {channel, ChannelName, ChannelPid}},
      % Now we notify the channel that a user wishes to join it.
      ChannelPid ! {self(), join_channel, {user, UserName, Sender}},
      % We do not forget to notify the sender that the user has successfully joined the channel.
      Sender ! {self(), channel_joined},
      % Finally, we proceed with the new state.
      master_actor(NewSubscriptions, dict:store(ChannelName, ChannelPid, Channels));

    {Sender, get_channel_history, ChannelName} ->
      % We forward requests for channel histories to the channel processes.
      dict:fetch(ChannelName, Channels) ! {Sender, get_channel_history},
      % We then proceed with the same state.
      master_actor(Subscriptions, Channels)
  end.

-spec log_out(UserPid  :: pid(),
              User     :: {user, string(), sets:set(string())},
              Channels :: dict:dict(string(), pid())) -> ok.
log_out(UserPid, {user, SubscriberName, Subscriptions}, Channels) ->
  % We notify all channels the user subscribes to that he wishes to leave them.
  %   We use a list comprehension here instead of lists:foreach/2, because the
  %   compiler optimizes the construction of the result list away, as per
  %   http://erlang.org/doc/efficiency_guide/listHandling.html#id67631.
  _ = [dict:fetch(Subscription, Channels) ! {self(), leave_channel, {user, SubscriberName, UserPid}} || Subscription <- sets:to_list(Subscriptions)],
  ok.

-spec find_or_create_channel(ChannelName  :: string(),
                             Channels     :: dict:dict(string(), pid())) -> pid().
%% @doc Finds an existing channel in `Channels' by `ChannelName' or creates a
%%   new one named `ChannelName'.
find_or_create_channel(ChannelName, Channels) ->
  case dict:find(ChannelName, Channels) of
    % If the channel already exists, we return its process identifier.
    {ok, ChannelPid} ->
      ChannelPid;
    % If it does not, we initialize a new channel and return its process identifier.
    error ->
      channel:initialize()
  end.

-spec subscribe(string()) -> fun(({user, string(), sets:set(string())}) -> {user, string(), sets:set(string())}).
%% @doc Generates a function which subscribes a user to `ChannelName'.
subscribe(ChannelName) ->
  fun({user, UserName, Subscriptions}) ->
    {user, UserName, sets:add_element(ChannelName, Subscriptions)}
  end.
