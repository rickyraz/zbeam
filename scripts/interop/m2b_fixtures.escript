#!/usr/bin/env escript
%% Generate deterministic pass-through frames with OTP's independent ETF encoder.
%% Run with OTP 25, 26 and 27; compare outputs byte-for-byte.
main(_) ->
    Peer = binary_to_term(<<131,88,119,9,"peer@host",4:32,0:32,2:32>>),
    A = binary_to_term(<<131,88,119,11,"native@host",1:32,0:32,1:32>>),
    B = binary_to_term(<<131,88,119,11,"native@host",2:32,0:32,1:32>>),
    Ref = binary_to_term(<<131,90,0,2,119,9,"peer@host",2:32,1:32,2:32>>),
    Reg = {6, Peer, '', zbeam_workers},
    Send = fun(Pid) -> {2, '', Pid} end,
    Request = fun(Cmd) -> {Peer, Ref, Cmd} end,
    Reply = fun(Body) -> {Ref, Body} end,
    Digest = crypto:hash(sha256, <<"abc">>),
    Vectors = [
        {discover_a, Reg, Request({discover,a})},
        {discover_b, Reg, Request({discover,b})},
        {hash_a, Send(A), Request({hash,<<"abc">>})},
        {hash_b, Send(B), Request({hash,<<"abc">>})},
        {stop_a, Send(A), Request(stop)},
        {reply_pid, Send(Peer), Reply({ok,A})},
        {reply_digest, Send(Peer), Reply({ok,Digest})},
        {reply_noproc, Send(Peer), Reply({error,noproc})},
        {reply_stop, Send(Peer), Reply(ok)},
        {monitor_pid, {19,Peer,A,Ref}, none},
        {demonitor_pid, {20,Peer,A,Ref}, none},
        {monitor_name, {19,Peer,zbeam_workers,Ref}, none},
        {exit_normal, {21,A,Peer,Ref,normal}, none}
    ],
    lists:foreach(fun({Name,Control,Payload}) ->
        C = term_to_binary(Control,[{minor_version,2}]),
        P = case Payload of none -> <<>>; _ -> term_to_binary(Payload,[{minor_version,2}]) end,
        Body = <<112,C/binary,P/binary>>,
        Frame = <<(byte_size(Body)):32,Body/binary>>,
        io:format("~s\t~s~n",[Name,binary:encode_hex(Frame)])
    end, Vectors).
