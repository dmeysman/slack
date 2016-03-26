%% @doc Process which receives messages from users and delivers them to channels.
%% @version 0.1.0
%% @author Dylan Meysmans <dmeysman@vub.ac.be>
%%   [http://student.vub.ac.be/~dmeysman]
%% @copyright 2016 Dylan Meysmans
-module(receiver).

-export([initialize/0, initialize_with/1, receiver_actor/1]).

initialize() ->
  initialize_with(dict:new()).

initialize_with(Channels) ->
  spawn_link(?MODULE, receiver_actor, [Channels]).

-spec receiver_actor(Channels :: dict:dict(string(), pid())) -> any().
receiver_actor(Channels) ->
  receive
    {Sender, log_out, UserName} ->
      % We delegate the work to the registered master process.
      master_actor ! {Sender, log_out, UserName};
      % We do not proceed, as there is no longer any use for us.

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
      dict:fetch(ChannelName, Channels) ! {Sender, get_channel_history};

    {_, new_channel, {channel, ChannelName, ChannelPid}} ->
      % We proceed with the new state.
      receiver_actor(dict:store(ChannelName, ChannelPid, Channels))
  end.
