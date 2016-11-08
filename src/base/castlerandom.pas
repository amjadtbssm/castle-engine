{
  Copyright 2016-2016 Eugene Loza, Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Custom random number generator (TCastleRandom). }
unit CastleRandom;

interface

{$I castleconf.inc}
{$I norqcheckbegin.inc} // the whole unit should be used without overflow checking, for speed

type
  { Custom, fast random number generator.
    Implementation of XorShift algorithm for random numbers generation.
    In some cases it works 2 to 3 times faster than native
    FPC random function. It also allows for multiple
    repeatable random seeds to support parallel pseudo-random sequences. }
  TCastleRandom = class(TObject)
  public
    { Create and initialize (seed) the random generator.
      Parameter RandomSeed value 0 indicates to use a random seed
      (derived from current time). }
    constructor Create(RandomSeed: LongWord = 0);
    { Initializes current seed. The seed must be a non-zero integer.
      Provide Zero value to initialize random seed based on current time. }
    procedure Initialize(RandomSeed: LongWord = 0);
    { Returns random float value in the 0..1 range. }
    function Random: single;
    { Returns random integer number in the 0..N-1 range. }
    function Random(N: LongInt): LongInt;
    { A relatively slow procedure to get a 64 bit integer random number. }
    function RandomInt64(N: int64): int64;
    { A simple Yes/No function that with 50% chance returns true or false.
      Something like throwing a coin... }
    function RandomBoolean: boolean;
    { Randomly provides "-1", "0" or "1" with equal chances. }
    function RandomSign: longint;
    { Returns a random number in 1 .. High(LongWord) range. }
    function Random32bit: LongWord;
  private
    Seed: LongInt;
    procedure XorShiftCycle;
    function GetRandomSeed: LongInt;
  end;

implementation

uses SysUtils, CastleTimeUtils; // required only for randomization based on "now" function
{p.s. Pay attention CastleTimeUtils.GetTickCount64 overrides SysUtils.GetTickCount64}

constructor TCastleRandom.Create(RandomSeed: LongWord);
begin
  Initialize(RandomSeed);
end;

procedure TCastleRandom.Initialize(RandomSeed: LongWord);
begin
  if RandomSeed = 0 then
  begin
    Seed := GetRandomSeed;
  end
  else seed := LongInt(RandomSeed);
end;

{$IFDEF UNIX}
//{$DEFINE USE_DEV_URANDOM}
{$ENDIF}

{$IFDEF USE_DEV_URANDOM}
function DEV_URANDOM: longint;
var dev_rnd: file of integer;
begin
  { algorithm according to http://wiki.freepascal.org/Dev_random
   /dev/urandom is a native *nix very high-quality random number generator.
   it's 1000 times slower than CastleRandom,
   but provides a perfect seed initialization. }
  //filemode := 0;
  AssignFile(dev_rnd, '/dev/urandom');
  reset(dev_rnd);
  read(dev_rnd,result);
  CloseFile(dev_rnd);
end;
{$ELSE}
{This procedure is relatively complex. However I was trying to solve
 a whole set of problems of random seeding. Including possible
 semi-simultaneous seeding requests by threads. On the other hand, there are
 more comments than the code itself :)
 I hope I've made everything right :) At least formal tests show it is so.}
var store_64bit_seed: QWord = 0; //this variable stores 64 bit seed for reusing
   wait_for_seed: boolean = false;
   Random_seed_count: QWord = 1843598; //some arbitrary variable to discern between threads
function Get_Randomseed: longint;
const date_multiplier: QWord = 30000000;  // approximate accuracy of the date
      date_order: QWord = 80000 * 30000000; // order of the "now*date_multiplier" variable
      {p.s. date_order will be true until year ~2119}
var c64: QWord; //current seed;
    b64: QWord; //additional seed for multi-threading safety
  procedure xorshift64; {$IFDEF SUPPORTS_INLINE} inline; {$ENDIF}
  begin
    c64:=c64 xor (c64 shl 12);
    c64:=c64 xor (c64 shr 25);
    c64:=c64 xor (c64 shl 27);
  end;
begin
  if random_seed_count<high(QWord) then
    inc(random_seed_count) // this will make 2 threads different even if they bypass wait_for_seed check somehow
  else
    random_seed_count := store_64bit_seed shr 32+1; //really, can this EVER happen???

  {prepare to do something idle in case there are multiple threads}
  c64 := random_seed_count;
  xorshift64;
  while wait_for_seed do xorshift64; //do something nearly useful while randomization is buisy

  wait_for_seed := true;     //prevents another randomization to start until this one is finished

  b64 := c64;   //and use our another random seed based on current randomization count;
  {can this actually damage randomness in case of randomization happens only once
   as b64 will be constant then?}

  if store_64bit_seed = 0 then begin
    {This random seed initialization follows SysUtils random.
     Actually it is a relatively bad initialization for random numbers
     comparing to Linux urandom.
     It provides a limited amount of random numbers and it has a step of
     15 or 16 ms, so it's not continuous. Moreover it has just 5 mlns of
     possible values per 24 hours while xorshift32 supports for max(LongWord) -
     i.e. we get ~800 times less variants or 2400 times less
     as a "normal" user doesn't run computer for longer than 8 hours.
     And even less than that in case the player runs the game near the time
     the computer starts - just 200 thousands of combinations for 1 hour.

     On the other hand that's relatively enough for a computer game.

     Another, much more serious problem is that initializing 2 random generators
     semi-simultaneously will seed them with EQUAL seeds
     which we obviously don't want to.}

    {so let's start by getting tick count as SysUtils does}
    c64 := gettickcount64;
    {just to make sure it's not zero. It's not really important here.}
    if c64 = 0 then c64 := 2903758934725;

    {"Trying to solve the problem" we do the following:}

    {make a 64-bit xorshift cycle}
    xorshift64;

    {We must make sure that such initialization will happen only once
     Xorshift64 will do the rest. That will provide us with truly random seeds
     while initializing multiple instances of CastleRandom semi-simultaneously
     We want this as soon as possible, if the next initialization happens
     "just now" - to be thread-safe.
     However, it's still safer to initialize multiple instances of CastleRandom
     outside of the threads}
    //store_64bit_seed := c64; //I hope wait_for_seed will do a better job for multi-threading

    {make a 64-bit xorshift cycle once more. Just to make really sure
     it has absolutely nothing to do with initial gettickcount64 anymore}
    xorshift64;

    {now we have to make sure adding "now" won't overflow our c64 variable
     and add a few xorshift64-cycles just for fun in case it will.}
    while (c64 > high(QWord)-date_order) do xorshift64;

    {to kill a random discretness introduced by gettickcount64 we add "now".
     "now" and gettickcount64 are not independent and, in fact, change
     synchronously. But after xorshift64 c64 has nothing
     left off gettickcount64 and therefore we introduce an additional
     semi-independent shift into the random seed}
    c64 += QWord(round(now*date_multiplier));
    {now we are sure that the player will get a different random seed even
     in case he/she launches the game exactly at the same milisecond since
     the Windows startup - different date&time will shift the random seed...
     unless he/she deliberately sets the date&time&tick to some specific value}

    {store another, more random 64 bit seed. Now we are not afraid another
     thread will pick it up and use it, as it's truly random right now}
    //store_64bit_seed := c64; //I hope wait_for_seed will do a better job for multi-threading
  end else
    c64 := store_64bit_seed; //else - just grab the last seed.

  {and another 64-bit xorshift cycle twice to kill everything left off "now"
   or just to cycle xorshift64 in case we have store_64bit_seed already initialized}
  xorshift64;
  c64 := c64 xor b64; //here we pack in our random_seed_count for threads
  xorshift64;

  {now leave higher 32-bits of c64 as a true random seed}
  result := longint(c64 shr 32);
  {and strictly demand it's not zero!
   adding a few xorshift64-cycles in case it does.}
  while result=0 do begin
    xorshift64;
    result := longint(c64 shr 32);
  end;

  {Eventually, store the final and truly random 64 bit seed.}
  store_64bit_seed := c64;
  {and release the next thread to continue if any pending...}
  wait_for_seed := false;
end;
{$ENDIF}

function TCastleRandom.GetRandomSeed: longint;
begin
  {$IFDEF USE_DEV_URANDOM}
    { guarantees initialization with absolutely random number provided by
      native *nix algorithm. }
    result := DEV_URANDOM;
  {$ELSE}
    result := Get_Randomseed;
  {$ENDIF}

  if result = 0 then result := maxint div 3; //to avoid the seed being zero
end;

procedure TCastleRandom.XorShiftCycle; {$IFDEF SUPPORTS_INLINE} inline; {$ENDIF}
begin
  { such implementation works a tiny bit faster (+4%) due to better optimization
    by compiler (uses CPU registers instead of a variable) }
  seed := ((seed xor (seed shl 1)) xor ((seed xor (seed shl 1)) shr 15)) xor
         (((seed xor (seed shl 1)) xor ((seed xor (seed shl 1)) shr 15)) shl 4);
  {seed := seed xor (seed shl 1);
  seed := seed xor (seed shr 15);
  seed := seed xor (seed shl 4); }
end;

{ This procedure is slow so it is better to use XorShiftCycle + direct access
  to seed private field instead }
function TCastleRandom.Random32bit: LongWord; {$IFDEF SUPPORTS_INLINE} inline; {$ENDIF}
begin
  XorShiftCycle;
  result := LongWord(seed);
end;

function TCastleRandom.Random: single;
const divisor: single = 1/maxint;
begin
  XorShiftCycle;
  result := divisor*LongInt(seed shr 1);       // note: we discard 1 bit of accuracy to gain speed
  //result := divisor*longint(XorShift shr 1);    // works slower
end;

{result := LongWord((int64(seed)*N) shr 32)// := seed mod N; works slower
//result := longint((int64(xorshift)*N) shr 32) // works slower}

// Adding  {$IFDEF SUPPORTS_INLINE} inline; {$ENDIF} makes this procedure
//  +35% effective. But I don't think it's a good idea
function TCastleRandom.Random(N: LongInt): LongInt;
begin
  XorShiftCycle;
  if N>1 then
    result := LongInt((int64(LongWord(seed))*N) shr 32)
  else
    result := 0
end;

{ Works much slower comparing to 32 bit version. And even slower than float version.
  Another problem is that it cycles the seed twice which might cause
  strange results if exact reproduction of the random sequence is required }
function TCastleRandom.RandomInt64(N: int64): int64;
begin
  // this line is copied from FPC system.inc
  result := int64((qword(Random32bit) or (qword(Random32bit) shl 32)) and $7fffffffffffffff);
  if N > 0 then
    result := result mod N
  else
    result := 0;
end;

function TCastleRandom.RandomBoolean: boolean;
begin
  XorShiftCycle;
  result := seed and %1 = 0   //can be %11 to provide for 1/4, %111 - 1/8 probability ...
end;

function TCastleRandom.RandomSign: longint;
begin
  XorShiftCycle;
  result := LongInt((int64(LongWord(seed))*3) shr 32)-1
end;

{$I norqcheckend.inc}

end.
