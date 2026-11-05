#!/usr/bin/env escript
%% Generate bounded custom-call frames with OTP's independent ETF encoder.
main(_) ->
    Peer = binary_to_term(<<131,88,119,9,"peer@host",4:32,0:32,2:32>>),
    A = binary_to_term(<<131,88,119,11,"native@host",1:32,0:32,1:32>>),
    Ref = binary_to_term(<<131,90,0,2,119,9,"peer@host",2:32,1:32,2:32>>),
    Send = fun(Pid) -> {2, '', Pid} end,
    Request = fun(Bin) -> {Peer, Ref, {call, Bin}} end,
    Reply = fun(Bin) -> {Ref, {ok, Bin}} end,
    Max = binary:copy(<<42>>, 32),
    Vectors = [
        {call_empty, Send(A), Request(<<>>)},
        {call_max, Send(A), Request(Max)},
        {reply_empty, Send(Peer), Reply(<<>>)},
        {reply_max, Send(Peer), Reply(Max)}
    ],
    lists:foreach(fun({Name, Control, Payload}) ->
        C = term_to_binary(Control, [{minor_version, 2}]),
        P = term_to_binary(Payload, [{minor_version, 2}]),
        Body = <<112, C/binary, P/binary>>,
        Frame = <<(byte_size(Body)):32, Body/binary>>,
        io:format("~s\t~s~n", [Name, binary:encode_hex(Frame)])
    end, Vectors).
