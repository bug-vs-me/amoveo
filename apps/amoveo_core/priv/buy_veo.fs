
( variables to customize this contract )
TradeID !
TradeNonce !
Date !
Ticker !
Amount !
Blockchain !
OracleStartHeight !
ProvideAddressTimeout !


( if they don't provide a bitcoin address in time, )
( then give the veo to type 2. )
ProvideAddressTimeout @ height <
if
    [ int 0, maximum ]
    int 0 int 1000
    return
else
then

( evidence to end this contract )
swap Address !
swap AddressSig !

( loading the trade receipt from consensus state, )
( because only the person who accepted this swap )
( request can choose the address to receive their )
( cryptocurrency on the other blockchain. )
car drop
car swap drop
car swap drop
car drop
int 32 split TradeID @ =2 or_die
int 65 split Acc2 !
TradeNonce @ =2 or_die

( check that Acc2 signed over Address where they want )
( to receive their BTC or whatever )
AddressSig @ Address @ Acc2 @ verify_sig or_die


( type 1 of first contract pays out to type 1 of second )
( contract. type 2 of first contract pays out to type 2 )
( of second contract )
[ [ maximum , int 0 ] ,
[ int 0 , maximum ] ]

( generating the root hash of the second smart contract )
( OracleStartHeight Blockchain Amount Ticker Date Address part2 call )
macro int_op binary 1 AA== ;
macro bin_op binary 1 Ag== ;
macro call_op binary 1 cQ== ;

int_op OracleStartHeight @ ++
bin_op ++ Blockchain @ bin_length ++ Blockchain @ ++
bin_op ++ Amount @ bin_length ++ Amount @ ++
bin_op ++ Ticker @ bin_length ++ Ticker @ ++
bin_op ++ Date @ bin_length ++ Date @ ++
bin_op ++ Address @ bin_length ++ Address @ ++
bin_op ++ int 32 ++ part2 ++ call_op ++
( print )
hash

( part2 print print drop )

int 0 int 1000
