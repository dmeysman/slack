%% @doc Process which encapsulates channel history and operates upon it.
%% @version 0.1.0
%% @author Dylan Meysmans <dmeysman@vub.ac.be>
%%   [http://student.vub.ac.be/~dmeysman]
%% @copyright 2016 Dylan Meysmans
-module(channel).

-export([initialize/0, initialize_with/2, channel_actor/2, broadcast/3]).

-spec initialize() -> pid().
%% @doc Creates a new channel process with subscribers nor history.
initialize() ->
  initialize_with(gb_trees:empty(), gb_trees:empty()).

-spec initialize_with(ActiveUsers :: gb_trees:tree(string(), pid()),
                      History     :: gb_trees:tree(integer(), {message, any(), any(), any(), integer()})) -> pid().
%% @doc Creates a new channel process with `ActiveUsers' and `History'.
initialize_with(ActiveUsers, History) ->
  spawn_link(?MODULE, channel_actor, [ActiveUsers, History]).

-spec channel_actor(ActiveUsers :: gb_trees:tree(string(), pid()),
                    History     :: gb_trees:tree(integer(), {message, any(), any(), any(), integer()})) -> no_return().
%% @doc Represents a channel process.
channel_actor(ActiveUsers, History) ->
  receive
    {Sender, join_channel, {user, ActiveUserName, ActiveUserPid} = ActiveUser} ->
      Sender ! {self(), joined_channel, ActiveUser},
      % We assume there are no duplicate user names.
      channel_actor(gb_trees:enter(ActiveUserName, ActiveUserPid, ActiveUsers), History);

    {Sender, leave_channel, {user, ActiveUserName, _} = ActiveUser} ->
      % We assume a user never leaves before joining and that for almost every
      %   user that leaves, another one joins. We therefore need not balance
      %   the tree by hand with gb_trees:balance/1.
      NewActiveUsers = gb_trees:delete(ActiveUserName, ActiveUsers),
      Sender ! {self(), left_channel, ActiveUser},
      channel_actor(NewActiveUsers, History);

    {Sender, get_channel_history} ->
      % To obtain the channel history as an ordered list, we discard the
      %   redundant timestamps.
      Sender ! {self(), channel_history, gb_trees:values(History)},
      channel_actor(ActiveUsers, History);

    {Sender, broadcast, {message, ActiveUserName, _, _, SendTime} = Message} ->
      broadcast(Sender, Message, gb_trees:values(gb_trees:delete_any(ActiveUserName, ActiveUsers))),
      % The channel history should always be in chronological order,
      %   we therefore store messages in a dictionary ordered by their timestamp.
      channel_actor(ActiveUsers, gb_trees:enter(SendTime, Message, History))
  end.

-spec broadcast(Sender  :: pid(),
                Message :: {message, any(), any(), any(), any()},
                Users   :: [pid()]) -> ok.
%% @doc Broadcasts `Message' to all elements of `Users' and notifies `Sender' when it is done.
broadcast(Sender, Message, Users) ->
  % We use a list comprehension here instead of lists:foreach/2, because the
  %   compiler optimizes the construction of the result list away, as per
  %   http://erlang.org/doc/efficiency_guide/listHandling.html#id67631.
  _ = [User ! {Sender, new_message, Message} || User <- Users],
  ok.
