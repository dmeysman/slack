# Slack

## Build

You can build Slack by invoking `erl` with the proper code path:

```
cd slack
erl -pa ebin
Erlang/OTP 18 [erts-7.3] [source] [64-bit] [smp:8:8] [async-threads:10] [hipe] [kernel-poll:false] [dtrace]

Eshell V7.3  (abort with ^G)
1> make:all([load]).
up_to_date
```
