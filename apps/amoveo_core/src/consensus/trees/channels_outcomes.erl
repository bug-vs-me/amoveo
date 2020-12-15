-module(channels_outcomes).
-export([data/0]).

data() ->
    <<"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">>.
    
