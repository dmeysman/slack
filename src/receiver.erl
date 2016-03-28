%% @doc Process which receives messages from users and delivers them to channels.
%% @version 0.1.0
%% @author Dylan Meysmans <dmeysman@vub.ac.be>
%%   [http://student.vub.ac.be/~dmeysman]
%% @copyright 2016 Dylan Meysmans
-module(receiver).

-export([initialize_with/3, receiver_actor/3]).

-spec initialize_with(UserPid  :: pid(),
                      User     :: {user, string(), sets:set(string())},
                      Channels :: dict:dict(string(), pid())) -> pid().
initialize_with(UserPid, User, Channels) ->
  spawn_link(?MODULE, receiver_actor, [UserPid, User, Channels]).

-spec receiver_actor(UserPid  :: pid(),
                     User     :: {user, string(), sets:set(string())},
                     Channels :: dict:dict(string(), pid())) -> ok.
receiver_actor(UserPid, {user, SubscriberName, Subscriptions}, Channels) ->
  % We notify all channels the user subscribes to that he wishes to join them.
  %   We use a list comprehension here instead of lists:foreach/2, because the
  %   compiler optimizes the construction of the result list away, as per
  %   http://erlang.org/doc/efficiency_guide/listHandling.html#id67631.
  _ = [dict:fetch(Subscription, Channels) ! {self(), join_channel, {user, SubscriberName, UserPid}} || Subscription <- sets:to_list(Subscriptions)],
  % We proceed without the user information, but we could continue to keep track
  %   of it in order to ensure the user only sends messages to channels he subscribes to.
  receiver_actor(Channels).

-spec receiver_actor(Channels :: dict:dict(string(), pid())) -> ok.
receiver_actor(Channels) ->
  receive
    {Sender, log_out, UserName} ->
      % We delegate the work to the registered master process.
      master_actor ! {Sender, log_out, UserName},
      % We do not proceed, as there is no longer any use for us.
      ok;

    {Sender, send_message, UserName, ChannelName, MessageText, SentTime} ->
      % We ask the channel to broadcast the message by fetching its pid through its name.
      dict:fetch(ChannelName, Channels) ! {self(), broadcast, {message, UserName, ChannelName, MessageText, SentTime}},
      Sender ! {self(), message_sent},
      receiver_actor(Channels);

    {Sender, join_channel, UserName, ChannelName} ->
      master_actor ! {Sender, self(), join_channel, UserName, ChannelName},
      receiver_actor(Channels);

    {Sender, get_channel_history, ChannelName} ->
      % We delegate the history retrieval to the channel process by fetching its pid through its name.
      dict:fetch(ChannelName, Channels) ! {Sender, get_channel_history},
      receiver_actor(Channels);

    {_, new_channel, {channel, ChannelName, ChannelPid}} ->
      % We proceed with the new state.
      receiver_actor(dict:store(ChannelName, ChannelPid, Channels))
  end.
