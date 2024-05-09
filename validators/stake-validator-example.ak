use aiken/dict
use aiken/fuzz
use aiken/hash.{Blake2b_224, Hash}
use aiken/interval
use aiken/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Redeemer, ScriptContext,
  Spend, Transaction, TransactionId, WithdrawFrom, placeholder,
}
use aiken/transaction/credential.{Address, Inline, Script, ScriptCredential}
use aiken/transaction/value
use aiken_design_patterns/stake_validator as stake_validator
use aiken_design_patterns/tests.{
  create_stake_credential, stakeCompare, test_oref, test_script_address,
}

validator {
  fn spend(_datum, _redeemer, ctx: ScriptContext) {
    stake_validator.spend(ctx)
  }

  fn withdraw(redeemer: Redeemer, ctx: ScriptContext) {
    stake_validator.withdraw(
      fn(_r, _own_validator, _tx) { True },
      redeemer,
      ctx,
    )
  }
}

// Test case for the spend validator
test spend_validator() {
  let own_ref =
    OutputReference {
      transaction_id: TransactionId {
        hash: #"ee220ba9258ef159bb44f0d3522b840a80475eac2df7176f2c513d59a2ead71f",
      },
      output_index: 0,
    }
  let script_purpose = Spend(own_ref)
  let own_val_hash: Hash<Blake2b_224, Script> =
    #"99999999999999999999999999999999999999999999999999999999"
  let input_utxo =
    Input {
      output_reference: own_ref,
      output: Output {
        address: Address {
          payment_credential: ScriptCredential(own_val_hash),
          stake_credential: None,
        },
        value: value.zero(),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let withdrawals =
    dict.new()
      |> dict.insert(Inline(ScriptCredential(own_val_hash)), 1, fn(_, _) { Less })
  let tx =
    Transaction {
      inputs: [input_utxo],
      reference_inputs: [],
      outputs: [],
      fee: value.zero(),
      mint: value.zero() |> value.to_minted_value(),
      certificates: [],
      withdrawals,
      validity_range: interval.everything(),
      extra_signatories: [],
      redeemers: dict.new(),
      datums: dict.new(),
      id: TransactionId {
        hash: #"0000000000000000000000000000000000000000000000000000000000000000",
      },
    }
  let ctx = ScriptContext { purpose: script_purpose, transaction: tx }
  spend(0, 0, ctx)
}

// Definition of a custom data type for spend input
type SpendInput {
  tx_id: ByteArray,
  val_hash: ByteArray,
  withdraw_amount: Int,
}

// Function to generate random spend input
fn random_spend_input() -> Fuzzer<SpendInput> {
  fuzz.map3(
    fuzz.bytearray_between(64, 64),
    fuzz.bytearray_between(56, 56),
    fuzz.int_at_least(1),
    fn(tx_id, val_hash, withdraw_amount) {
      SpendInput(tx_id, val_hash, withdraw_amount)
    },
  )
}

// Property test to verify the spend validator
test prop_spend_validator(r via random_spend_input()) {
  let own_ref =
    OutputReference {
      transaction_id: TransactionId { hash: r.tx_id },
      output_index: 0,
    }
  let script_purpose = Spend(own_ref)
  let own_val_hash: Hash<Blake2b_224, Script> = r.val_hash
  let input_utxo =
    Input {
      output_reference: own_ref,
      output: Output {
        address: Address {
          payment_credential: ScriptCredential(own_val_hash),
          stake_credential: None,
        },
        value: value.zero(),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let withdrawals =
    dict.new()
      |> dict.insert(
          Inline(ScriptCredential(own_val_hash)),
          r.withdraw_amount,
          fn(_, _) { Less },
        )
  let tx =
    Transaction {
      inputs: [input_utxo],
      reference_inputs: [],
      outputs: [],
      fee: value.zero(),
      mint: value.zero() |> value.to_minted_value(),
      certificates: [],
      withdrawals,
      validity_range: interval.everything(),
      extra_signatories: [],
      redeemers: dict.new(),
      datums: dict.new(),
      id: TransactionId {
        hash: #"0000000000000000000000000000000000000000000000000000000000000000",
      },
    }
  let ctx = ScriptContext { purpose: script_purpose, transaction: tx }
  spend(0, 0, ctx)
}

// Test case for the withdraw validator
test withdraw_validator() {
  let redeemer = 1
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

// Definition of a custom data type for withdraw input
type WithdrawInput {
  bs: ByteArray,
  redeemer: Int,
}

// Function to generate random withdraw input
fn random_withdraw_input() -> Fuzzer<WithdrawInput> {
  fuzz.map2(
    fuzz.bytearray_between(56, 56),
    fuzz.int(),
    fn(bs, r) { WithdrawInput(bs, r) },
  )
}

// Property test to verify the withdraw validator
test prop_withdraw_validator(r via random_withdraw_input()) {
  let ctx =
    ScriptContext {
      purpose: WithdrawFrom(Inline(ScriptCredential(r.bs))),
      transaction: transaction.placeholder(),
    }
  withdraw(r.redeemer, ctx)
}

// Example Transaction Test //

test t_tx() {
  let scriptHash = #"e60add40af9cfecd31f6b509ede4bd3031b1af8144fae1ec748a37cc"
  let scriptAddress = test_script_address(scriptHash)
  let authValue =
    value.merge(value.from_lovelace(2), value.from_asset(#"aced", #"aced", 1))

  let withdraw0 =
    dict.from_ascending_list(
      [(create_stake_credential(scriptHash), 0)],
      stakeCompare,
    )

  let oref1 = test_oref(#"face", 1)
  let oref2 = test_oref(#"cafe", 2)
  let oref3 = test_oref(#"dead", 1)
  let oref4 = test_oref(#"face", 2)
  let oref5 = test_oref(#"cafe", 5)
  let oref6 = test_oref(#"dead", 3)

  let inDatum = #"1234"

  let redeemer = #"1234"

  let input1 =
    Input {
      output_reference: oref1,
      output: Output {
        address: scriptAddress,
        value: authValue,
        datum: InlineDatum(inDatum),
        reference_script: None,
      },
    }

  let input2 =
    Input {
      output_reference: oref2,
      output: Output {
        address: scriptAddress,
        value: authValue,
        datum: InlineDatum(inDatum),
        reference_script: None,
      },
    }

  let input3 =
    Input {
      output_reference: oref3,
      output: Output {
        address: scriptAddress,
        value: authValue,
        datum: InlineDatum(inDatum),
        reference_script: None,
      },
    }
  let input4 =
    Input {
      output_reference: oref4,
      output: Output {
        address: scriptAddress,
        value: authValue,
        datum: InlineDatum(inDatum),
        reference_script: None,
      },
    }

  let input5 =
    Input {
      output_reference: oref5,
      output: Output {
        address: scriptAddress,
        value: authValue,
        datum: InlineDatum(inDatum),
        reference_script: None,
      },
    }

  let input6 =
    Input {
      output_reference: oref6,
      output: Output {
        address: scriptAddress,
        value: authValue,
        datum: InlineDatum(inDatum),
        reference_script: None,
      },
    }

  let output1 =
    Output {
      address: scriptAddress,
      value: authValue,
      datum: InlineDatum(inDatum),
      reference_script: None,
    }

  let output2 =
    Output {
      address: scriptAddress,
      value: authValue,
      datum: InlineDatum(inDatum),
      reference_script: None,
    }

  let output3 =
    Output {
      address: scriptAddress,
      value: authValue,
      datum: InlineDatum(inDatum),
      reference_script: None,
    }
  let output4 =
    Output {
      address: scriptAddress,
      value: authValue,
      datum: InlineDatum(inDatum),
      reference_script: None,
    }

  let output5 =
    Output {
      address: scriptAddress,
      value: authValue,
      datum: InlineDatum(inDatum),
      reference_script: None,
    }

  let output6 =
    Output {
      address: scriptAddress,
      value: authValue,
      datum: InlineDatum(inDatum),
      reference_script: None,
    }

  // two inputs from the same script address
  let inputs =
    [input1, input2, input3, input4, input5, input6]
  let outputs =
    [output1, output2, output3, output4, output5, output6]

  let tx =
    Transaction {
      ..placeholder(),
      inputs: inputs,
      outputs: outputs,
      withdrawals: withdraw0,
    }

  let ctx1 = ScriptContext { transaction: tx, purpose: Spend(oref1) }
  let ctx2 = ScriptContext { transaction: tx, purpose: Spend(oref2) }
  let ctx3 = ScriptContext { transaction: tx, purpose: Spend(oref3) }
  let ctx4 = ScriptContext { transaction: tx, purpose: Spend(oref4) }
  let ctx5 = ScriptContext { transaction: tx, purpose: Spend(oref5) }
  let ctx6 = ScriptContext { transaction: tx, purpose: Spend(oref6) }

  spend(inDatum, redeemer, ctx1)? && spend(inDatum, redeemer, ctx2)? && spend(
    inDatum,
    redeemer,
    ctx3,
  )? && spend(inDatum, redeemer, ctx4)? && spend(inDatum, redeemer, ctx5)? && spend(
    inDatum,
    redeemer,
    ctx6,
  )?
}
