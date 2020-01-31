-module(rng_challenge_tx).
-export([go/4, make_dict/10]).
-include("../../records.hrl").
%-record(rng_challenge_tx, {pubkey, nonce, fee, id, sortition_id, parent_id, n}).
%-record(rng_challenge, {id, result_id, parent_id, pubkey, hashes, timestamp, refunded, n}).

make_dict(From, ID, SID, PID, PT, N, StartHash, EndHash, Proof, Fee) ->
    Acc = trees:get(accounts, From),
    #rng_challenge_tx{pubkey = From, 
                      nonce = Acc#acc.nonce + 1, 
                      fee = Fee,
                      id = ID,
                      sortition_id = SID,
                      parent_id = PID,
                      parent_type = PT,
                      start_hash = StartHash,
                      end_hash = EndHash,
                      proof = Proof,
                      n = N
                     }.

go(Tx, Dict, NewHeight, NonceCheck) ->
    #rng_challenge_tx{nonce = Nonce,
                      fee = Fee,
                      pubkey = From,
                      sortition_id = SID,
                      parent_id = PID,
                      parent_type = PT,
                      start_hash = StartHash,
                      end_hash = EndHash,
                      id = ID,
                      proof = Proof,
                      n = N
                     } = Tx,
    32 = size(StartHash),
    32 = size(EndHash),
    Type = case PT of
               0 -> rng_result;
               1 -> rng_challenge
           end,
    Facc = accounts:dict_update(From, Dict, -Fee, Nonce),
    Dict2 = accounts:dict_write(Facc, Dict),
    S = sortition:dict_get(SID, Dict2),
    #sortition{
                rng_value = <<0:256>>%verifies that this sortition has not decided on the rng yet
     } = S,
    X = Type:dict_get(PID, Dict2),
    Hashes = Type:hashes(X),
    Size = 64,
    KeyLength = 2,
    M = mtree:new_empty(KeyLength, Size, 0),
    CFG = mtree:cfg(M),
    HashPair = <<StartHash/binary, EndHash/binary>>,
    true = verify:proof(Hashes, HashPair, Proof, CFG),
    {RID, Radix, Mantissa} = 
        case Type of
            rng_result -> 
                {PID, 4, 151};
            rng_challenge ->
                RC = rng_challenge:dict_get(PID, Dict2),
                #rng_challenge{result_id = R_0,
                              hashes = H_0,
                              many = ManyLeft} = RC,
                false = (<<0:256>> == H_0),%a result needs to have been provided that can be challenged.
                <<Radix0:6, Mantissa0:10>> = ManyLeft,
                {R_0, (Radix0-1), Mantissa0}
        end,
    %if radix is 0, handle with rng_cleanup
    %TODO
    <<Many:16>> = <<Radix:6, Mantissa:10>>,
    false = (Radix == 0),
    Result = rng_result:dict_get(RID, Dict2),
    SID = Result#rng_result.sortition_id,
    <<HashStart:256, HashEnd:256>> = HashPair,
    NRC = rng_challenge:new(ID, PID, RID, From, NewHeight, N, <<HashStart:256>>, <<HashEnd:256>>, Many),
    rng_challenge:dict_write(NRC, Dict2).
