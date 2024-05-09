use aiken/dict
use aiken/fuzz
use aiken/hash.{Blake2b_224, Hash}
use aiken/interval
use aiken/transaction.{
  Redeemer, ScriptContext, ScriptPurpose, Transaction, TransactionId,
  WithdrawFrom,
}
use aiken/transaction/credential.{Inline, Script, ScriptCredential}
use aiken/transaction/value
use aiken_design_patterns/merkelized_validator.{WithdrawRedeemer} as merkelized_validator
use aiken_design_patterns/tests.{
  create_stake_credential, scriptCompare, stakeCompare, test_oref,
  test_script_address,
}
use aiken_design_patterns/utils.{sum_of_squares}

// Definition of a custom validator for spending transactions
validator(stake_validator: Hash<Blake2b_224, Script>) {
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

// Definition of a custom validator for withdrawal transactions
validator {
  fn withdraw(redeemer: WithdrawRedeemer<Int, Int>, ctx: ScriptContext) {
    merkelized_validator.withdraw(sum_of_squares, redeemer, ctx)
  }
}

// Test case for the spend validator function
test spend_validator() {
  let stake_validator: Hash<Blake2b_224, Script> =
    #"99999999999999999999999999999999999999999999999999999999"
  let redeemer: Data = WithdrawRedeemer { input_args: [2, 4], results: [20] }
  let redeemers: dict.Dict<ScriptPurpose, Redeemer> =
    dict.new()
      |> dict.insert(
          WithdrawFrom(Inline(ScriptCredential(stake_validator))),
          redeemer,
          fn(_, _) -> Ordering { Less },
        )
  let tx =
    Transaction {
      inputs: [],
      reference_inputs: [],
      outputs: [],
      fee: value.zero(),
      mint: value.zero() |> value.to_minted_value(),
      certificates: [],
      withdrawals: dict.new(),
      validity_range: interval.everything(),
      extra_signatories: [],
      redeemers,
      datums: dict.new(),
      id: TransactionId {
        hash: #"0000000000000000000000000000000000000000000000000000000000000000",
      },
    }
  let ctx =
    ScriptContext {
      purpose: WithdrawFrom(
        Inline(
          ScriptCredential(
            #"99999999999999999999999999999999999999999999999999999999",
          ),
        ),
      ),
      transaction: tx,
    }
  spend(stake_validator, 2, 4, ctx)
}

// Test case for the withdraw validator function
test withdraw_validator() {
  let redeemer: WithdrawRedeemer<Int, Int> =
    WithdrawRedeemer { input_args: [1, 2, 3, 4], results: [30] }
  let ctx =
    ScriptContext {
      purpose: WithdrawFrom(
        Inline(
          ScriptCredential(
            #"99999999999999999999999999999999999999999999999999999999",
          ),
        ),
      ),
      transaction: transaction.placeholder(),
    }
  withdraw(redeemer, ctx)
}

// Definition of a custom data type for withdrawal input
type WithdrawInput {
  xs: List<Int>,
  bs: ByteArray,
}

// Function to generate random withdrawal input
fn random_withdraw_input() -> Fuzzer<WithdrawInput> {
  fuzz.map2(
    fuzz.list(fuzz.int()),
    fuzz.bytearray_between(56, 56),
    fn(xs, bs) { WithdrawInput { xs, bs } },
  )
}

// Property test to verify withdraw validator
test prop_withdraw_validator(r via random_withdraw_input()) {
  let expected_sum_of_squares = utils.sum_of_squares(r.xs)
  let redeemer: WithdrawRedeemer<Int, Int> =
    WithdrawRedeemer { input_args: r.xs, results: expected_sum_of_squares }
  let ctx =
    ScriptContext {
      purpose: WithdrawFrom(Inline(ScriptCredential(r.bs))),
      transaction: transaction.placeholder(),
    }
  withdraw(redeemer, ctx)
}

// Definition of a custom data type for spend input
type SpendInput {
  x: Int,
  y: Int,
  bs: ByteArray,
}

// Function to generate random spend input
fn random_spend_input() -> Fuzzer<SpendInput> {
  fuzz.map3(
    fuzz.int_between(-4, 4),
    fuzz.int_between(-4, 4),
    fuzz.bytearray_between(56, 56),
    fn(x, y, bs) { SpendInput { x, y, bs } },
  )
}

// Property test to verify the spend validator
test prop_spend_validator(r via random_spend_input()) {
  let xs =
    [r.x, r.y]
  let expected_sum_of_squares = utils.sum_of_squares(xs)
  let stake_validator: Hash<Blake2b_224, Script> = r.bs
  let redeemer: Data =
    WithdrawRedeemer { input_args: xs, results: expected_sum_of_squares }
  let redeemers: dict.Dict<ScriptPurpose, Redeemer> =
    dict.new()
      |> dict.insert(
          WithdrawFrom(Inline(ScriptCredential(stake_validator))),
          redeemer,
          fn(_, _) -> Ordering { Less },
        )
  let tx =
    Transaction {
      inputs: [],
      reference_inputs: [],
      outputs: [],
      fee: value.zero(),
      mint: value.zero() |> value.to_minted_value(),
      certificates: [],
      withdrawals: dict.new(),
      validity_range: interval.everything(),
      extra_signatories: [],
      redeemers,
      datums: dict.new(),
      id: TransactionId {
        hash: #"0000000000000000000000000000000000000000000000000000000000000000",
      },
    }
  let ctx =
    ScriptContext {
      purpose: WithdrawFrom(Inline(ScriptCredential(r.bs))),
      transaction: tx,
    }
  spend(stake_validator, r.x, r.y, ctx)
}

// Example Transaction Test //

test t_tx() {
  let spendHash = #"c1acf08f57b3e8f84b3152ed40b6b5e5548d892cfe2ecf3caa174ed1"
  let stakeHash = #"b3fa7f3416e51ea354249e6469ab8489ce8e0187f3567491a71788f0"
  let spendAddress = test_script_address(spendHash)
  let authValue =
    value.merge(value.from_lovelace(2), value.from_asset(#"aced", #"aced", 1))

  let withdraw0 =
    dict.from_ascending_list(
      [(create_stake_credential(stakeHash), 0)],
      stakeCompare,
    )

  let oref1 = test_oref(#"face", 1)
  let oref2 = test_oref(#"cafe", 2)
  let oref3 = test_oref(#"dead", 1)
  let oref4 = test_oref(#"face", 2)
  let inDatum = 2

  let redeemer = 2

  let results = 32

  let input1 =
    Input {
      output_reference: oref1,
      output: Output {
        address: spendAddress,
        value: authValue,
        datum: InlineDatum(inDatum),
        reference_script: None,
      },
    }

  let input2 =
    Input {
      output_reference: oref2,
      output: Output {
        address: spendAddress,
        value: authValue,
        datum: InlineDatum(inDatum),
        reference_script: None,
      },
    }

  let input3 =
    Input {
      output_reference: oref3,
      output: Output {
        address: spendAddress,
        value: authValue,
        datum: InlineDatum(inDatum),
        reference_script: None,
      },
    }

  let input4 =
    Input {
      output_reference: oref4,
      output: Output {
        address: spendAddress,
        value: authValue,
        datum: InlineDatum(inDatum),
        reference_script: None,
      },
    }

  let output1 =
    Output {
      address: spendAddress,
      value: authValue,
      datum: InlineDatum(inDatum),
      reference_script: None,
    }

  let output2 =
    Output {
      address: spendAddress,
      value: authValue,
      datum: InlineDatum(inDatum),
      reference_script: None,
    }

  let output3 =
    Output {
      address: spendAddress,
      value: authValue,
      datum: InlineDatum(inDatum),
      reference_script: None,
    }

  let output4 =
    Output {
      address: spendAddress,
      value: authValue,
      datum: InlineDatum(inDatum),
      reference_script: None,
    }

  // two inputs from the same script address
  let inputs =
    [input1, input2, input3, input4]
  let outputs =
    [output1, output2, output3, output4]

  let wRedeemer: Data =
    WithdrawRedeemer { input_args: [inDatum, redeemer], results: [results] }

  let redeemers =
    dict.new()
      |> dict.insert(
          WithdrawFrom(create_stake_credential(stakeHash)),
          wRedeemer,
          scriptCompare,
        )

  let tx =
    Transaction {
      ..placeholder(),
      inputs: inputs,
      outputs: outputs,
      redeemers: redeemers,
      withdrawals: withdraw0,
    }

  let ctx1 = ScriptContext { transaction: tx, purpose: Spend(oref1) }
  let ctx2 = ScriptContext { transaction: tx, purpose: Spend(oref2) }
  let ctx3 = ScriptContext { transaction: tx, purpose: Spend(oref3) }
  let ctx4 = ScriptContext { transaction: tx, purpose: Spend(oref4) }

  let ctx9 =
    ScriptContext {
      transaction: tx,
      purpose: WithdrawFrom(create_stake_credential(stakeHash)),
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
}
