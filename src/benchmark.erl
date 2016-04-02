-module(benchmark).

-export([test_send_message/1, test_log_in/1,
    initialize_server/3,
    initialize_server_and_some_clients/5, receive_new_messages/2, test_send_message_debug/3]).

%% Benchmark helpers
%-define(NUMBER_OF_USERS, 2000).
%-define(NUMBER_OF_ONLINE_USERS, 2000).
%-define(NUMBER_OF_ACTIVE_USERS, 100).
%-define(NUMBER_OF_CHANNELS, 10).

% erl -pa ebin +S 4 -noshell -s benchmark test_send_message 5000 2000 100 10 -s init stop > test.txt
% erl -pa ebin +S 4 -noshell -s benchmark test_log_in 10000 10000 100 -s init stop > test.txt

-define(CHANNEL_NAME, 1).

%http://erlangcentral.org/wiki/index.php/Introduction_to_Load_Testing_with_Tsung#What_is_load_testing.3F

% Recommendation: run each test at least 30 times to get statistically relevant
% results.
run_benchmark(Name, Fun, Times) ->
    ThisPid = self(),
    lists:foreach(fun (N) ->
        % Recommendation: to make the test fair, each new test run is to run in
        % its own, newly created Erlang process. Otherwise, if all tests run in
        % the same process, the later tests start out with larger heap sizes and
        % therefore probably do fewer garbage collections. Also consider
        % restarting the Erlang emulator between each test.
        % Source: http://erlang.org/doc/efficiency_guide/profiling.html
        spawn(fun () ->
            run_benchmark_once(Name, Fun, N),
            ThisPid ! done
        end),
        receive done ->
            ok
        end
    end, lists:seq(1, Times)).

run_benchmark_once(Name, Fun, N) ->
    io:format("Running benchmark ~s: ~p~n", [Name, N]),

    % Start timers
    % Tips:
    % * Wall clock time measures the actual time spent on the benchmark.
    %   I/O, swapping, and other activities in the operating system kernel are
    %   included in the measurements. This can lead to larger variations.
    %   os:timestamp() is more precise (microseconds) than
    %   statistics(wall_clock) (milliseconds)
    % * CPU time measures the actual time spent on this program, summed for all
    %   threads. Time spent in the operating system kernel (such as swapping and
    %   I/O) is not included. This leads to smaller variations but is
    %   misleading.
    statistics(runtime),        % CPU time, summed for all threads
    StartTime = os:timestamp(), % Wall clock time

    % Run
    Fun(),

    % Get and print statistics
    % Recommendation [1]:
    % The granularity of both measurement types can be high. Therefore, ensure
    % that each individual measurement lasts for at least several seconds.
    % [1] http://erlang.org/doc/efficiency_guide/profiling.html
    {_, Time1} = statistics(runtime),
    Time2 = timer:now_diff(os:timestamp(), StartTime),
    io:format("CPU time = ~p ms~nWall clock time = ~p ms~n",
        [Time1, Time2 / 1000.0]),
    io:format("~s done~n", [Name]).

%% Benchmarks

initialize_server(NUMBER_OF_USERS, NUMBER_OF_CHANNELS, NUMBER_OF_SUBSCRIBED_CHANNELS) ->
    rand:seed_s(exsplus, {0, 0, 0}),

    ChannelNames = lists:seq(1, NUMBER_OF_CHANNELS),
    UserNames = lists:seq(1, NUMBER_OF_USERS),

    Channels = lists:foldl(fun (Number, ChannelsSoFar) ->
      dict:store(Number, channel:initialize(), ChannelsSoFar)
    end,
    dict:new(),
    ChannelNames),

    Users = dict:from_list(lists:map(fun (Name) ->
        Subscriptions = lists:seq(1, NUMBER_OF_SUBSCRIBED_CHANNELS),
        %Subscriptions = [rand:uniform(?NUMBER_OF_CHANNELS)],
        User = {user, Name, sets:from_list(Subscriptions)},
        {Name, User}
    end,
    UserNames)),

    master:initialize_with(Users, Channels),
    % wait to be sure all masters are started
    % receive
    %    slack_ready -> ok
    % end,
    Users.


% Creates a server with channels and users, and logs in users.
% `Fun(I)` is executed on the clients after log in, where I is the client's
% index, which is also its corresponding user's name.
initialize_server_and_some_clients(NUMBER_OF_USERS, NUMBER_OF_ONLINE_USERS, NUMBER_OF_CHANNELS, NUMBER_OF_SUBSCRIBED_CHANNELS, Fun) ->
    Users = initialize_server(NUMBER_OF_USERS, NUMBER_OF_CHANNELS, NUMBER_OF_SUBSCRIBED_CHANNELS),
    BenchmarkerPid = self(),

    %% TODO:little cheat to make sure our masters are started
   % timer:sleep(2000),

    % we login the first ?NUMBER_OF_ONLINE_USERS user that are registered
    Clients = lists:map(fun (I) ->
        ClientPid = spawn_link(fun () ->
            {WorkerPid, logged_in} = server:log_in(master_actor, I),
            BenchmarkerPid ! {logged_in, I, WorkerPid},
            Fun(I)
        end),
        {I, ClientPid}
        end,
        lists:seq(1, NUMBER_OF_ONLINE_USERS)),

    % wait for all to be logged in
    Clientss = lists:map(fun ({I, ClientPid}) ->
            receive {logged_in, I, WorkerPid} ->
                {I, {ClientPid, WorkerPid}}
            end
        end,
        Clients),

    {Users, dict:from_list(Clientss)}.


test_log_in(Args) ->
    [NUMBER_OF_USERS, NUMBER_OF_CHANNELS, NUMBER_OF_SUBSCRIBED_CHANNELS]
        = lists:map(fun(X) -> list_to_integer(atom_to_list(X)) end, Args),
    run_benchmark("test_log_in",
        fun () ->
            initialize_server(NUMBER_OF_USERS, NUMBER_OF_CHANNELS, NUMBER_OF_SUBSCRIBED_CHANNELS),
            BenchmarkerPid = self(),

            %% TODO:little cheat to make sure our masters are started
            %timer:sleep(2000),

            io:format("%NUMBER_OF_USERS=~p NUMBER_OF_ONLINE_USERS=~p NUMBER_OF_CHANNELS=~p ~n",
                [NUMBER_OF_USERS, NUMBER_OF_USERS, NUMBER_OF_CHANNELS]),

            StartTime = os:timestamp(), % Wall clock time
            Clients = lists:map(fun (I) ->
                ClientPid = spawn_link(fun () ->
                    {WorkerPid, logged_in} = server:log_in(master_actor, I),
                    BenchmarkerPid ! {logged_in, I, WorkerPid}
                end),
                {I, ClientPid}
                end,
                lists:seq(1, NUMBER_OF_USERS)),

            % wait for all to be logged in
            lists:map(fun ({I, ClientPid}) ->
                    receive {logged_in, I, WorkerPid} ->
                        {I, {ClientPid, WorkerPid}}
                    end
                end,
                Clients),

            Time2 = timer:now_diff(os:timestamp(), StartTime),
            io:format("~f~n", [Time2 / 1000.0])
        end,
        1).

% Send a message for 1000 users, and wait for all of them to be broadcast
% (repeated 30 times).
% 3. the latency of sending a message
test_send_message(Args) ->
    [NUMBER_OF_USERS, NUMBER_OF_ONLINE_USERS, NUMBER_OF_ACTIVE_USERS]
        = lists:map(fun(X) -> list_to_integer(atom_to_list(X)) end, Args),
    run_benchmark("test_send_message",
        fun () ->
            BenchmarkerPid = self(),
            ClientFun = fun(I) ->
                receive_new_messages(BenchmarkerPid, I)
            end,
            {Users, Clients} =
            initialize_server_and_some_clients(NUMBER_OF_USERS, NUMBER_OF_ONLINE_USERS, 1, 1, ClientFun),

            % from the ?NUMBER_OF_ONLINE_USERS users,
            % we check which one are subscribed and therefore joined channel ?CHANNEL_NAME
            ClientsSubscribedTo1 = lists:filter(fun (UN) ->
                {user, UN, Subscriptions} = dict:fetch(UN, Users),
                sets:is_element(?CHANNEL_NAME, Subscriptions)
            end, dict:fetch_keys(Clients)),

            %io:format("% total size = ~p~n", [length(ClientsSubscribedTo1)]),

            % from those we take ?NUMBER_OF_ACTIVE_USERS which are going to send messages to that ?CHANNEL_NAME
            ChosenClients = lists:sublist(ClientsSubscribedTo1, NUMBER_OF_ACTIVE_USERS),

            send_message_for_users(ChosenClients, ClientsSubscribedTo1, Clients)
        end,
        1).

test_send_message_debug(NUMBER_OF_USERS, NUMBER_OF_ONLINE_USERS, NUMBER_OF_ACTIVE_USERS) ->
    run_benchmark("send_message_for_each_user",
        fun () ->
            BenchmarkerPid = self(),
            ClientFun = fun(I) ->
                receive_new_messages(BenchmarkerPid, I)
            end,
            {Users, Clients} =
            initialize_server_and_some_clients(NUMBER_OF_USERS, NUMBER_OF_ONLINE_USERS, 1, 1, ClientFun),

            % from the ?NUMBER_OF_ONLINE_USERS users,
            % we check which one are subscribed and therefore joined channel ?CHANNEL_NAME
            ClientsSubscribedTo1 = lists:filter(fun (UN) ->
                {user, UN, Subscriptions} = dict:fetch(UN, Users),
                sets:is_element(?CHANNEL_NAME, Subscriptions)
            end, dict:fetch_keys(Clients)),

            %io:format("% total size = ~p~n", [length(ClientsSubscribedTo1)]),

            % from those we take ?NUMBER_OF_ACTIVE_USERS which are going to send messages to that ?CHANNEL_NAME
            ChosenClients = lists:sublist(ClientsSubscribedTo1, NUMBER_OF_ACTIVE_USERS),

            send_message_for_users(ChosenClients, ClientsSubscribedTo1, Clients)
        end,
        30).

% test_send_random_message(NUMBER_OF_USERS, NUMBER_OF_ONLINE_USERS, NUMBER_OF_ACTIVE_USERS, NUMBER_OF_CHANNELS) ->
%     run_benchmark("random message",
%         fun () ->
%             BenchmarkerPid = self(),
%             ClientFun = fun(I) ->
%                 receive_new_messages(BenchmarkerPid, I)
%             end,
%             {Users, Clients} =
%             initialize_server_and_some_clients(NUMBER_OF_USERS, NUMBER_OF_ONLINE_USERS, 1, 1, ClientFun),
%
%             %every active user has to send a message
%             dict:map(fun(SenderName, {ClientPid, Channels})->
%                 % select random channel from channel list
%                 Channel = get_channel(Channels),
%
%                 %send message to channel
%                 ClientPid ! {self(), send_message, Channel, "test"},
%                 receive
%                     {SenderName, message_sent} -> ok
%                 end,
%
%                 % all other online users following the channel should get this message
%                 % remember only those users substribed to the channel
%                 ClientsSubscribedToChannel =
%                     dict:filter(fun (_UserName, {_ReceiverPid, ReceiverChannels}) ->
%                         lists:member(Channel, ReceiverChannels) end,
%                 Clients),
%
%                 %remove sender from list
%                 ExpectedReceivers = dict:erase(SenderName, ClientsSubscribedToChannel),
%                 dict:map(fun (ReceiverName, _ReceiverData)->
%                             receive {ReceiverName, received_message} -> ok end
%                         end,
%                         ExpectedReceivers) end,
%                 Clients) end,
%         30).

% stress test one channel all -> all
send_message_for_users(ChosenClients, ClientsSubscribedToChannel, Clients) ->

    io:format("%chosen clients to send message =  ~p~n", [length(ChosenClients)]),
    io:format("%subscribed to channel 1 =  ~p~n", [length(ClientsSubscribedToChannel)]),
    AmountOfMessages = length(ClientsSubscribedToChannel) * length(ChosenClients),
    io:format("%messages sent =  ~p~n", [AmountOfMessages]),
    %timer:sleep(2500),

    % For each of the chosen users, send a message to channel 1.

    io:format("% start =  ~p~n", [length(ClientsSubscribedToChannel) * length(ChosenClients)]),
    StartTime = os:timestamp(), % Wall clock time
    lists:foreach(fun (I) ->
            {_ClientPid, WorkerPid} = dict:fetch(I, Clients),
            server:send_message(WorkerPid, I, ?CHANNEL_NAME, "Test")
        end,
        ChosenClients),

    %erlang:display("% waiting for replies"),

    lists:foreach(fun (I) ->
        % We expect responses from everyone except the sender.
        %StartTime = os:timestamp(), % Wall clock time
        ExpectedResponses = lists:delete(I, ClientsSubscribedToChannel),
        lists:foreach(fun (ClientUserName) ->
            receive
                {received_message, ClientUserName} -> ok
            end
        end,
        ExpectedResponses)
        %Time2 = timer:now_diff(os:timestamp(), StartTime)
        %io:format("Wall clock time for ~p messages was ~p ms~n",[length(ExpectedResponses), Time2 / 1000.0])
    end,
    ChosenClients),

    Time2 = timer:now_diff(os:timestamp(), StartTime),
    io:format("% time for ~p messages was ~p microseconds~n",[AmountOfMessages, Time2]),
    if
        Time2 == 0 ->
            io:format("throughput(time==0)=~f ~n", [AmountOfMessages / (Time2 / 1.0)]);
        true ->
            io:format("throughput=~f ~n", [AmountOfMessages / (Time2 / 1000000.0)])
    end.


% Helper function: receives new messages and notifies benchmarker for each
% received message.
receive_new_messages(BenchmarkerPid, I) ->
    receive
        {_, new_message, _} ->
            %{_, Time2} = erlang:process_info(self(), messages),
            %io:format("Wall clock time = ~p~n", [self()]),
            BenchmarkerPid ! {received_message, I},
            receive_new_messages(BenchmarkerPid, I)
    end.
