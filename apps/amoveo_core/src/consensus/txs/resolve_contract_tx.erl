-module(resolve_contract_tx).
-export([go/4, make_dict/6]).
-include("../../records.hrl").

make_dict(From, Contract, CID, Evidence, Prove, Fee) ->
    A = trees:get(accounts, From),
    Nonce = A#acc.nonce + 1,
    #resolve_contract_tx{from = From, nonce = Nonce, fee = Fee, contract = Contract, evidence = Evidence, prove = Prove, contract_id = CID}.
    
go(Tx, Dict, NewHeight, _) ->
    #resolve_contract_tx{
    from = From,
    nonce = Nonce,
    fee = Fee,
    contract = ContractBytecode,
    contract_id = CID,
    evidence = Evidence,%like the script sig in bitcoin
    prove = Prove%on-chain state to include.
   } = Tx,
    Facc = accounts:dict_update(From, Dict, -Fee, Nonce),
    Dict2 = accounts:dict_write(Facc, Dict),
    Contract = contracts:dict_get(CID, Dict2),
    #contract{
      many_types = Many,
      nonce = ContractNonce,
      last_modified = LM,
      delay = Delay,
      closed = 0,
      result = Result,
      source = Source,
      source_type = SourceType,
      volume = Volume
     } = Contract,
    CH = hash:doit(ContractBytecode),
    CID = contracts:make_id(CH, Many,Source,SourceType),%verify that this is the correct code for this contract.
    case run(NewHeight, Prove, Evidence, ContractBytecode, Dict2) of
        {error, Error} ->
            io:fwrite("\n in resolve_contract_tx, contract has an error\n"),
            Dict2;
        Data2 ->
            case chalang:stack(Data2) of
                [<<CNonce:32>>,<<CDelay:32>>,<<CResult:32>>|_] when (CNonce > ContractNonce) ->
                    %all the money goes to one user
                    Contract2 = Contract#contract{
                                  result = <<CResult:256>>,
                                  nonce = CNonce,
                                  delay = CDelay,
                                  last_modified = NewHeight
                                 },
                    contracts:dict_write(Contract2, Dict2);
                [<<CNonce:32>>,<<CDelay:32>>,<<ResultCH:256>>,Matrix|_] ->
                    %contract is being converted into a different contract defined by ResultCH and the length of rows in the matrix.
                    %for every subcurrency type in the original contract, we need to specify a rule for how many of which kinds of subcurrency they will receive in the new contract. We use a matrix for this. Each row is for one original subcurrency.
                    B1 = CNonce > ContractNonce,
                    B2 = is_list(Matrix),
                    B3 = (Many == length(Matrix)),
                    RMany = length(hd(Matrix)),
                    B4 = all_lengths(RMany, Matrix),
                    TwoE32 = 4294967295,%(2**32 - 1) highest expressible value in chalang integers.
                    B5 = column_sum(TwoE32, Matrix),
                    B6 = B1 and B2 and B3 and B4 and B5,
                    if
                        not(B6) ->
                            if
                                not(B1) -> io:fwrite("resolve contract tx, nonce is too low to update contract.\n");
                                not(B2) -> io:fwrite("resolve_contract_tx, matrix is misformatted.\n");
                                not(B3) -> io:fwrite("resolve_contract_tx, matrix has wrong number of rows.\n");
                                not(B4) -> io:fwrite("resolve_contract_tx, matrix has a row with the wrong length.\n");
                                not(B5) -> io:fwrite("resolve_contract_tx, matrix does not conserve the total number of veo.\n")
                            end,
                            Dict2;
                        true ->
                    
                            RCID = contracts:make_id(<<ResultCH:256>>, RMany,Source,SourceType),
                            RContract = contracts:dict_get(RCID, Dict2),
                            RContract2 = 
                                case RContract of
                                    empty ->
                                   %the resultCID doesn't exist, create that shareable contract.
                                        contracts:new(<<ResultCH:256>>, RMany, Source, SourceType);
                                    _ -> RContract
                                end,
                            MT = mtree:new_empty(5, 32, 0),
                            Leaves = make_leaves(RCID, Matrix, MT),
                            {MRoot, M2} = mtree:store_batch(Leaves, 1, MT),
                            RootHash = mtree:root_hash(MRoot, M2),
                            RContract3 = RContract#contract{
                                           result = RootHash,
                                           nonce = CNonce,
                                           delay = CDelay,
                                           last_modified = NewHeight
                                          },
                            contracts:dict_write(RContract3, Dict2)
                    end;
                Output ->
                    io:fwrite("in resolve_contract_tx, contract has invalid output\n"),
                    Dict2
            end
    end.
    
all_lengths(_, []) -> true;
all_lengths(L, [H|T]) -> 
    B1 = is_list(H),
    B2 = (L == length(H)),
    if
        (B1 and B2) -> all_lengths(L, T);
        true -> false
    end.

column_sum(_, [[]|_]) -> ok;
column_sum(N, M) -> 
    N = column_sum2(0, M),
    M2 = tails(M),
    column_sum(N, M2).
column_sum2(N, []) -> N;
column_sum2(N, [[H|_]|R]) ->
    column_sum2(H+N, R).
tails([]) -> [];
tails([H|T]) -> 
    [tl(H)|tails(T)].

make_leaves(CID, Matrix, MT) ->
    CFG = mtree:cfg(MT),
    L1 =  leaf:new(1, CID, 0, CFG),
    make_leaves2([L1], 2, Matrix, CFG).
make_leaves2(X, _, [], _) -> X;
make_leaves2(X, N, [R|T], CFG) -> 
    SR = serialize_row(R, <<>>),
    RH = hash:doit(SR),
    L = leaf:new(N, RH, 0, CFG),
    make_leaves2([L|X], N+1, T, CFG).
serialize_row([], B) -> B;
serialize_row([H|T], A) -> 
    A2 = <<A/binary, H:32>>,
    R = serialize_row(T, A2).

run(NewHeight, Prove, Evidence, ContractBytecode, Dict2) ->
    true = chalang:none_of(Evidence),
    Funs = governance:dict_get_value(fun_limit, Dict2),
    Vars = governance:dict_get_value(var_limit, Dict2),
    OpGas = governance:dict_get_value(time_gas, Dict2),
    RamGas = governance:dict_get_value(space_gas, Dict2),

    State = chalang:new_state(NewHeight, 0, 0),
    ProveCode = spk:prove_facts(Prove, Dict2, NewHeight),
    AllCode = <<Evidence/binary, ProveCode/binary, ContractBytecode/binary>>,
    Data = chalang:data_maker(OpGas, RamGas, Vars, Funs, <<>>, AllCode, State, constants:hash_size(), 2, false),
    chalang:run5(AllCode, Data).
    
