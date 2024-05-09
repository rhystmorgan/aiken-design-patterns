<!-- vim-markdown-toc GFM -->
# Table of Contents

* [Aiken Library for Common Design Patterns in Cardano Smart Contracts](#aiken-library-for-common-design-patterns-in-cardano-smart-contracts)
  * [How to Use](#how-to-use)
  * [How to Run Package Tests](#how-to-run-package-tests)
  * [Provided Patterns](#provided-patterns)
    * [Stake Validator](#stake-validator)
      * [Endpoints](#endpoints)
    * [UTxO Indexers](#utxo-indexers)
      * [Singular UTxO Indexer](#singular-utxo-indexer)
        * [One-to-One](#one-to-one)
        * [One-to-Many](#one-to-many)
      * [Multi UTxO Indexer](#multi-utxo-indexer)
    * [Transaction Level Validator Minting Policy](#transaction-level-validator-minting-policy)
    * [Validity Range Normalization](#validity-range-normalization)
    * [Merkelized Validator](#merkelized-validator)

<!-- vim-markdown-toc -->

# Aiken Library for Common Design Patterns in Cardano Smart Contracts

To help facilitate faster development of Cardano smart contracts, we present a
collection of tried and tested modules and functions for implementing common
design patterns.

## How to Use

Install the package with `aiken`:

```bash
aiken package add anastasia-labs/aiken-design-patterns --version main
```

And you'll be able to import functions of various patterns:

```rs
use aiken_design_patterns/merkelized_validator as merkelized_validator
use aiken_design_patterns/multi_utxo_indexer as multi_utxo_indexer
use aiken_design_patterns/singular_utxo_indexer as singular_utxo_indexer
use aiken_design_patterns/stake_validator as stake_validator
use aiken_design_patterns/tx_level_minter as tx_level_minter
```

Check out `validators/` to see how the exposed functions can be used.

## How to Run Package Tests

Here are the steps to compile and run the included tests:

1. Clone the repo and navigate inside:

```bash
git clone https://github.com/Anastasia-Labs/aiken-design-patterns
cd aiken-design-patterns
```

2. Run the build command, which both compiles all the functions/examples and
   also runs the included unit tests:

```sh
aiken build
```

3. Execute the test suite:

```sh
aiken check
```

![aiken-design-patterns.gif](/assets/images/aiken-design-patterns.gif)

Test results:

![test_report.png](/assets/images/test_report.png)

## Provided Patterns

### Stake Validator

This module offers two functions meant to be used within a multi-validator for
implementing a "coupled" stake validator logic.

The primary application for this is the so-called "withdraw zero trick," which
is most effective for validators that need to go over multiple inputs.

With a minimal spending logic (which is executed for each UTxO), and an
arbitrary withdrawal logic (which is executed only once), a much more optimized
script can be implemented.

#### Endpoints

`spend` merely looks for the presence of a withdrawal (with arbitrary amount)
from its own reward address.

`withdraw` takes a custom logic that requires 3 arguments:

  1. Redeemer (arbitrary `Data`)
  2. Script's validator hash (`Hash<Blake2b_224, Script>`)
  3. Transaction info (`Transaction`)

```rust

validator {
  fn spend(_datum, _redeemer, ctx: ScriptContext) {
    stake_validator.spend(ctx)
    // checks its withdrawing
  }

  fn withdraw(redeemer: Redeemer, ctx: ScriptContext) {
    stake_validator.withdraw(
      // applies transaction logic
      fn(_r, _own_validator, _tx) { True },
      // always succeeds
      redeemer,
      ctx,
    )
  }
}

```

Your multi validator `spend` just checks for the `withdraw` signature

so you need to do this for the test:

```rust

fn create_stake_credential(
  s: Hash<Blake2b_224, Script>,
) -> Referenced<Credential> {
  Inline(ScriptCredential(s))
}

test t_tx() {
  let scriptHash = #"e60add40af9cfecd31f6b509ede4bd3031b1af8144fae1ec748a37cc"

  let inDatum = #"1234"

  let redeemer = #"1234"

  let withdraw0 = // add withdrawl value && script hash 
    dict.from_ascending_list(
      [(create_stake_credential(scriptHash), 0)],
      stakeCompare,
    )

  let tx =
    Transaction {
      ..placeholder(),
      inputs: inputs,
      outputs: outputs,
      withdrawals: withdraw0, // include it in the transaction
    }
  
  let ctx1 = ScriptContext { transaction: tx, purpose: Spend(oref1) }

  spend(inDatum, redeemer, ctx1)?

}

```

The purpose of withdraw zero is to allow multiple transactions to be processed 
at the same time, without the cost increase associated with including the full 
validator for evoery transaction.


### UTxO Indexers

The primary purpose of this pattern is to offer a more optimized solution for
a unique mapping between one input UTxO to one or many output UTxOs.

#### Singular UTxO Indexer

##### One-to-One

By specifying the redeemer type to be a pair of integers (`(Int, Int)`), the
validator can efficiently pick the input UTxO, match its output reference to
make sure it's the one that's getting spent, and similarly pick the
corresponding output UTxO in order to perform an arbitrary validation between
the two.

The provided example validates that the two are identical, and each carries a
single state token apart from Ada.

```rust

validator(state_token_symbol: PolicyId) {
  fn spend(_datum, redeemer: (Int, Int), ctx: ScriptContext) {
    singular_utxo_indexer.spend(
      // validation logic function is described here
      fn(in_utxo, out_utxo) {
        // checks the inputs and outputs match with a exact match auth token
        authentic_input_is_reproduced_unchanged(
          state_token_symbol,
          None,
          in_utxo,
          out_utxo,
        )
      },
      redeemer,
      ctx,
    )
  }
}

```

so you need to do this for the test:

```rust

let redeemer1 = (0, 0) // the redeemer references tx inputs and outputs of the script
let redeemer2 = (1, 1) // this means we need to calculate them lexicographically 
let redeemer3 = (2, 2) // outputs can be defined in tx building so that isnt an issue
let redeemer4 = (3, 3)
let redeemer5 = (4, 4)
let redeemer6 = (5, 5)

```

If you are doing 1-1 `in-out` validation this is a great way to increase 
throughput of transactions

##### One-to-Many

Here the validator looks for a set of outputs for the given input, through a
redeemer of type `(Int, List<Int>)` (output indices are required to be in
ascending order to disallow duplicates). To make the abstraction as efficient
as possible, the provided higher-order function takes 3 validation logics:

1. A function that validates the spending `Input` (single invocation).
2. A function that validates the input UTxO against a corresponding output
   UTxO. Note that this is executed for each associated output.
3. A function that validates the collective outputs. This also runs only once.
   The number of outputs is also available for this function (its second
   argument).

on-chain recursion is expensive and we dont want to make redundant checks 
recursively, so we only recurse on the `per output` data.

This allows us to limit the on-chain computation and will help us save space 
and fees.

```rust

validator(_state_token_symbol: PolicyId, _state_token_name: AssetName) {
  fn spend(_datum, redeemer: (Int, List<Int>), ctx: ScriptContext) {
    singular_utxo_indexer.spend(
      fn(_input) { True },
      // validates spending inputs
      fn(_in_utxo, _out_utxo) { True },
      // validates inputs against each output index
      fn(_out_utxos, _output_count) { True },
      // validates all outputs
      redeemer,
      ctx,
    )
  }
}

```

This allows us all of the same improvements as the `UTxOIndexer` but with the 
added ability to resolve multiple outputs.

so we are expected to run tests like this:

```rust

let redeemer1 = (0, [0, 1, 2])
let redeemer2 = (1, [3, 4, 5])

let tx = Transaction { ..placeholder(), inputs: inputs, outputs: outputs }

let ctx1 = ScriptContext { transaction: tx, purpose: Spend(oref1) }
let ctx2 = ScriptContext { transaction: tx, purpose: Spend(oref2) }

spend(
  #"aced", #"", inDatum, redeemer1, ctx1)? && 
spend(
  #"aced", #"", inDatum, redeemer2, ctx2)?

```

#### Multi UTxO Indexer

While the singular variant of this pattern is primarily meant for the spending
endpoint of a contract, a multi UTxO indexer utilizes the stake validator
provided by this package. And therefore the spending endpoint can be taken
directly from `stake_validator`.

Subsequently, spend redeemers are irrelevant here. The redeemer of the
withdrawal endpoint is expected to be a properly sorted list of pairs of
indices (for the one-to-one case), or a list of one-to-many mappings of
indices.

It's worth emphasizing that it is necessary for this design to be a
multi-validator as the staking logic filters inputs that are coming from a
script address which its validator hash is identical to its own.

The distinction between one-to-one and one-to-many variants here is very
similar to the singular case, so please refer to [its section above](#singular-utxo-indexer) for
more details.

The primary difference is that here, input indices should be provided for the
_filtered_ list of inputs, i.e. only script inputs, unlike the singular variant
where the index applies to all the inputs of the transaction. This slight
inconvenience is for preventing extra overhead on-chain.

This is basically a combination of the previous ones

it is a staking pair which checks there is a matching set of token inputs and 
outputs

it checks every utxo has a `state_token_symbol` and `state_token_name` in the 
example code

```rust
validator(state_token_symbol: PolicyId, state_token_name: AssetName) {
  fn spend(_datum, _redeemer, ctx: ScriptContext) {
    stake_validator.spend(ctx)
    // checks for withdrawal
  }

  fn withdraw(redeemer: List<(Int, Int)>, ctx: ScriptContext) {
    // for each input output index, check the values match with auth token
    multi_utxo_indexer.withdraw(
      // applies transaction logic to utxo pairs
      fn(in_utxo, out_utxo) {
        // checks inputs and outputs match with an authToken
        authentic_input_is_reproduced_unchanged(
          state_token_symbol,
          Some(state_token_name),
          in_utxo,
          out_utxo,
        )
      },
      redeemer,
      ctx,
    )
  }
}
```

I tested it with 6 ins-outs and checking for withdrawal on any transaction 
instead of validating stake and it was 50% more efficient on both mem and cpu

I only have a passing test, i need to write more tests and use more 
interesting examples of transactions to really understand how i could apply it.

I could write an example that validates every transaction with a policy, but 
with different token names ( which we can use to pair ins and outs )

#### Spend Validation

```rust

pub fn spend(ctx: ScriptContext) -> Bool {
  expect ScriptContext { transaction: tx, purpose: Spend(own_ref) } = ctx

  let Transaction { inputs, withdrawals, .. } = tx

  // finds its input according to outRef
  let Output { address: own_addr, .. } =
    resolve_output_reference(inputs, own_ref)

  // Stake Credential Pointer Hash CIP-19
  let own_withdrawal = Inline(own_addr.payment_credential)

  // Arbitrary withdrawal from this script is required.
  dict.has_key(withdrawals, own_withdrawal)
}

```

Spending validation just checks that there is a withdrawal signature that 
matches its script hash.

so you need to make sure you are doing this in the test: 

```rust
fn create_stake_credential(
  s: Hash<Blake2b_224, Script>,
) -> Referenced<Credential> {
  Inline(ScriptCredential(s))
}

fn stakeCompare(
  left: Referenced<Credential>,
  right: Referenced<Credential>,
) -> Ordering {
  if left == right {
    Equal
  } else {
    Less
  }
}

test t_tx1() {
  let scriptHash = #"b32d1dbb92d894538a14f672e45998889904bd82bd0ea78ea3e6e6fb"

  let withdraw0 =
    dict.from_ascending_list(
      [(create_stake_credential(scriptHash), 0)],
      stakeCompare,
    )
  
  let tx =
      Transaction {
        ..placeholder(),
        inputs: inputs,
        outputs: outputs,
        withdrawals: withdraw0,
      }

  let ctx1 = ScriptContext { transaction: tx, purpose: Spend(oref1) }

  spend(#"aced", #"", inDatum, redeemer1, ctx1)? 

```

#### Withdrawal Validation

```rust

pub fn withdraw(
  validation_logic: fn(Output, Output) -> Bool,
  redeemer: List<(Int, Int)>,
  ctx: ScriptContext,
) -> Bool {
  // applies validation logic to a list of input outputs with token
  stake_validator.withdraw(
    fn(indicesData, own_validator, tx) {
      // validates if indeces have pass validation
      // get ins & outs
      let Transaction { inputs, outputs, .. } = tx
      // make a list of all ownScript inputs
      let (script_inputs, script_input_count) =
        list.foldr(
          inputs,
          ([], 0),
          // starting point
          // for each input check if it has script credential
          fn(i, acc_tuple) {
            expect Input {
              output: Output {
                address: Address {
                  payment_credential: ScriptCredential(script),
                  ..
                },
                ..
              } as o,
              ..
            } =
              // grab output
              i
            // if script credential matches, save output to list and inc
            if script == own_validator {
              let (acc, count) = acc_tuple
              ([o, ..acc], count + 1)
            } else {
              // return current list 
              acc_tuple
            }
          },
        )
      expect indices: List<(Int, Int)> = indicesData
      let (_, _, input_index_count) =
        // checks validation logic against redeemer indeces
        list.foldl(
          indices,
          (-1, -1, 0),
          // starting point
          fn(curr, acc) {
            let (in0, out0, count) = acc
            let (in1, out1) = curr
            if in1 > in0 && out1 > out0 {
              expect Some(in_utxo) = script_inputs |> list.at(in1)
              expect Some(out_utxo) = outputs |> list.at(out1)
              // applies validation logic to utxo pair
              if validation_logic(in_utxo, out_utxo) {
                (in1, out1, count + 1)
              } else {
                fail @"Validation failed"
              }
            } else {
              // Input and output indices must be ordered to disallow
              // duplicates.
              fail @"Input and output indices must be in ascending orders"
            }
          },
        )
      (script_input_count == input_index_count)?
    },
    redeemer,
    ctx,
  )
}

```

This function gets a list of all the script inputs and maps the index to a 
list outputs at the redeemer.

the redeemer is an index pair

if the input and output at the redeemers match and they both have one of the 
same token (parameter) then validations will pass

so you need to do this in a test:

```rust

fn create_stake_credential(
  s: Hash<Blake2b_224, Script>,
) -> Referenced<Credential> {
  Inline(ScriptCredential(s))
}

fn withPurpose(hash: ByteArray) -> ScriptPurpose {
  let stake = create_stake_credential(hash)
  WithdrawFrom(stake)
}

test t_tx1() {
  let scriptHash = #"b32d1dbb92d894538a14f672e45998889904bd82bd0ea78ea3e6e6fb"
  let authValue =
    value.merge(value.from_lovelace(2), value.from_asset(#"aced", #"", 1))
  
  let withdraw0 =
    dict.from_ascending_list(
      [(create_stake_credential(scriptHash), 0)],
      stakeCompare,
    )

  let redeemer1 = (0, 0) // index for each spending tx pair

  let tx =
      Transaction {
        ..placeholder(),
        inputs: inputs,
        outputs: outputs,
        withdrawals: withdraw0,
      }

    let ctx1 = ScriptContext { transaction: tx, purpose: withPurpose(scriptHash) }

  withdraw(#"aced", #"", redeemerList, ctx1)?


```

### Transaction Level Validator Minting Policy

Very similar to the [stake validator](#stake-validator), this design pattern
utilizes a multi-validator comprising of a spend and a minting endpoint.

The role of the spendig input is to ensure the minting endpoint executes. It
does so by looking at the mint field and making sure a non-zero amount of its
asset (where its policy is the same as the multi-validator's hash, and its name
is specified as a parameter) are getting minted/burnt.

The arbitrary logic is passed to the minting policy so that it can be executed
a single time for a given transaction.

### Validity Range Normalization

The datatype that models validity range in Cardano currently allows for values
that are either meaningless, or can have more than one representations. For
example, since the values are integers, the inclusive flag for each end is
redundant and can be omitted in favor of a predefined convention (e.g. a value
should always be considered inclusive).

In this module we present a custom datatype that essentially reduces the value
domain of the original validity range to a smaller one that eliminates
meaningless instances and redundancies.

The datatype is defined as following:

```rs
pub type NormalizedTimeRange {
  ClosedRange { lower: Int, upper: Int }
  FromNegInf  {             upper: Int }
  ToPosInf    { lower: Int             }
  Always
}
```

The exposed function of the module (`normalize_time_range`), takes a
`ValidityRange` and returns this custom datatype.

### Merkelized Validator

Since transaction size is limited in Cardano, some validators benefit from a
solution which allows them to delegate parts of their logics. This becomes more
prominent in cases where such logics can greatly benefit from optimization
solutions that trade computation resources for script sizes (e.g. table
lookups can take up more space so that costly computations can be averted).

This design pattern offers an interface for off-loading such logics into an
external withdrawal script, so that the size of the validator itself can stay
within the limits of Cardano.

> [!NOTE]
> While currently the sizes of reference scripts are essentially irrelevant,
> they'll soon impose additional fees.
> See [here](https://github.com/IntersectMBO/cardano-ledger/issues/3952) for
> more info.

The exposed `spend` function from `merkelized_validator` expects 3 arguments:

1. The hash of the withdrawal validator that performs the computation.
2. The list of arguments expected by the underlying logic.
3. The `Dict` of all redeemers within the current script context.

This function expects to find the given stake validator in the `redeemers` 
list, such that its redeemer is of type `WithdrawRedeemer` (which carries the 
list of input arguments and the list of expected outputs), makes sure provided 
inputs match the ones given to the validator through its redeemer, and returns 
the outputs (which are carried inside the withdrawal redeemer) so that you can
safely use them.

For defining a withdrawal logic that carries out the computation, use the
exposed `withdraw` function. It expects 3 arguments:

1. The computation itself. It has to take a list of generic inputs, and return
   a list of generic outputs.
2. A redeemer of type `WithdrawRedeemer<a, b>`. Note that `a` is the type of
   input arguments, and `b` is the type of output arguments.
3. The script context.

It validates that the puropse is withdrawal, and that given the list of inputs,
the provided function yields identical outputs as the ones provided via the
redeemer.

The merkle script requires a signature from a parameterised `scriptHash`, it 
is an extension of the `withdrawZero` Pattern which allows for an increased 
throughput per transaction.

Using this pattern will allow you to reference a `stakeValidator` by parameter 
and then apply the validator logic to multiple inputs and outputs decreasing 
validator footprint and saving space on transactions (and improving the user 
experience).

in the example the stake validator allows withdrawal if the spending 
validators datum and redeemer `sumOfSquares` to the results value in its 
redeemer

```rust

//Stake Validator as param
validator(stake_validator: Hash<Blake2b_224, Script>) {
  // Spend Int Datum & Int Redeemer
  fn spend(x: Int, y: Int, ctx: ScriptContext) {
    let ScriptContext { transaction: tx, .. } = ctx
    let xData: Data = x
    let yData: Data = y
    expect [sumData] =
      merkelized_validator.spend(stake_validator, [xData, yData], tx.redeemers)
    expect sum: Int = sumData
    sum < 42
  }
}

validator {
  fn withdraw(redeemer: WithdrawRedeemer<Int, Int>, ctx: ScriptContext) {
    merkelized_validator.withdraw(sum_of_squares, redeemer, ctx)
  }
}

```

This example is limiting because it checks the `sumOfSquares` is less than 42, 
but naturally without this limitation we can do as many tx's as we can squeeze 
in.

So you need to do this for the test:

```rust

let spendHash = #"c1acf08f57b3e8f84b3152ed40b6b5e5548d892cfe2ecf3caa174ed1"
let stakeHash = #"b3fa7f3416e51ea354249e6469ab8489ce8e0187f3567491a71788f0"

let authValue =
  value.merge(value.from_lovelace(2), value.from_asset(#"aced", #"aced", 1))

let withdraw0 =
  dict.from_ascending_list(
    [(create_stake_credential(stakeHash), 0)],
    stakeCompare,
  )

let inDatum = 2

let redeemer = 2

let results = 32 // we are testing 4 inputs (2 * 2 + 2 * 2) * 4 inputs

let tx =
    Transaction {
      ..placeholder(),
      inputs: inputs,
      outputs: outputs,
      redeemers: redeemers,
      withdrawals: withdraw0,
    }

spend(stakeHash, inDatum, redeemer, ctx1)? && spend(
  stakeHash,
  inDatum,
  redeemer,
  ctx2,
)? && spend(stakeHash, inDatum, redeemer, ctx3)? && spend(
  stakeHash,
  inDatum,
  redeemer,
  ctx4,
)?

```

This is the most advanced version of the withdraw0 trick that we have.

You can offload different logic to different stake validators almost like 
modular logic, meaning you only include relevant logic in your validators as 
and when needed.

I havent tested it at this point, but i imagine we can offload logic in this 
way for different redeemer cases, so instead of including a whole validator 
with all of the redeemer cases in a transaction, we just include the relevant 
staking validators.

I want to build out test cases for this, i will share when i have some 
tangible examples with a better understanding of the limitations.
