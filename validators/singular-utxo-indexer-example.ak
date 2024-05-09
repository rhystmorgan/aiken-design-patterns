use aiken/dict
use aiken/fuzz
use aiken/interval
use aiken/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, ScriptContext, Spend,
  Transaction, TransactionId, placeholder,
}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value
use aiken_design_patterns/singular_utxo_indexer as singular_utxo_indexer
use aiken_design_patterns/tests.{test_oref, test_script_address}
use aiken_design_patterns/utils.{authentic_input_is_reproduced_unchanged}

validator(state_token_symbol: value.PolicyId) {
  fn spend(_datum, redeemer: (Int, Int), ctx: ScriptContext) {
    singular_utxo_indexer.spend(
      fn(in_utxo, out_utxo) {
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

// Test case for the spend validator function
test spend_validator() {
  let own_ref =
    OutputReference {
      transaction_id: TransactionId {
        hash: #"ee220ba9258ef159bb44f0d3522b840a80475eac2df7176f2c513d59a2ead71f",
      },
      output_index: 0,
    }
  let script_purpose = Spend(own_ref)
  let state_token_symbol =
    #"99999999999999999999999999999999999999999999999999999999"
  let token_name = #"02"
  let own_val_hash = #"88888888888888888888888888888888888888888888888888888888"
  let input_utxo =
    Input {
      output_reference: own_ref,
      output: Output {
        address: Address {
          payment_credential: ScriptCredential(own_val_hash),
          stake_credential: None,
        },
        value: value.add(
          value.from_lovelace(2_000_000),
          state_token_symbol,
          token_name,
          1,
        ),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let output =
    Output {
      address: Address {
        payment_credential: ScriptCredential(own_val_hash),
        stake_credential: None,
      },
      value: value.add(
        value.from_lovelace(2_000_000),
        state_token_symbol,
        token_name,
        1,
      ),
      datum: NoDatum,
      reference_script: None,
    }
  let redeemer = (0, 0)
  let arbitrary_datum = 0
  let tx =
    Transaction {
      inputs: [input_utxo],
      reference_inputs: [],
      outputs: [output],
      fee: value.zero(),
      mint: value.zero() |> value.to_minted_value(),
      certificates: [],
      withdrawals: dict.new(),
      validity_range: interval.everything(),
      extra_signatories: [],
      redeemers: dict.new(),
      datums: dict.new(),
      id: TransactionId {
        hash: #"0000000000000000000000000000000000000000000000000000000000000000",
      },
    }
  let ctx = ScriptContext { purpose: script_purpose, transaction: tx }
  spend(state_token_symbol, arbitrary_datum, redeemer, ctx)
}

// Definition of a custom data type for spend input
type SpendInput {
  state_token_symbol: ByteArray,
  tx_id: ByteArray,
  val_hash: ByteArray,
  token_name: ByteArray,
}

// Function to generate random spend input
fn random_spend_input() -> Fuzzer<SpendInput> {
  fuzz.map4(
    fuzz.bytearray_between(56, 56),
    fuzz.bytearray_between(64, 64),
    fuzz.bytearray_between(56, 56),
    fuzz.bytearray_between(0, 32),
    fn(state_token_symbol, tx_id, val_hash, token_name) {
      SpendInput(state_token_symbol, tx_id, val_hash, token_name)
    },
  )
}

// Property test to verify the spend validator function
test prop_spend_validator(r via random_spend_input()) {
  let own_ref =
    OutputReference {
      transaction_id: TransactionId { hash: r.tx_id },
      output_index: 0,
    }
  let script_purpose = Spend(own_ref)
  let input_utxo =
    Input {
      output_reference: own_ref,
      output: Output {
        address: Address {
          payment_credential: ScriptCredential(r.val_hash),
          stake_credential: None,
        },
        value: value.add(
          value.from_lovelace(2_000_000),
          r.state_token_symbol,
          r.token_name,
          1,
        ),
        datum: NoDatum,
        reference_script: None,
      },
    }
  let output =
    Output {
      address: Address {
        payment_credential: ScriptCredential(r.val_hash),
        stake_credential: None,
      },
      value: value.add(
        value.from_lovelace(2_000_000),
        r.state_token_symbol,
        r.token_name,
        1,
      ),
      datum: NoDatum,
      reference_script: None,
    }
  let redeemer = (0, 0)
  let arbitrary_datum = 0
  let tx =
    Transaction {
      inputs: [input_utxo],
      reference_inputs: [],
      outputs: [output],
      fee: value.zero(),
      mint: value.zero() |> value.to_minted_value(),
      certificates: [],
      withdrawals: dict.new(),
      validity_range: interval.everything(),
      extra_signatories: [],
      redeemers: dict.new(),
      datums: dict.new(),
      id: TransactionId {
        hash: #"0000000000000000000000000000000000000000000000000000000000000000",
      },
    }
  let ctx = ScriptContext { purpose: script_purpose, transaction: tx }
  spend(r.state_token_symbol, arbitrary_datum, redeemer, ctx)
}

// Example Transaction Test //

test t_tx() {
  let scriptHash = #"04bd1633f41d8740246706defe79d182d46188f54534187511f80534"
  let scriptAddress = test_script_address(scriptHash)
  let authValue =
    value.merge(value.from_lovelace(2), value.from_asset(#"aced", #"", 1))

  let oref1 = test_oref(#"face", 1)
  let oref2 = test_oref(#"face", 2)
  let oref3 = test_oref(#"face", 3)
  let oref4 = test_oref(#"face", 4)
  let oref5 = test_oref(#"face", 5)
  let oref6 = test_oref(#"face", 6)
  let inDatum = #"1234"

  let redeemer1 = (0, 0)
  let redeemer2 = (1, 1)
  let redeemer3 = (2, 2)
  let redeemer4 = (3, 3)
  let redeemer5 = (4, 4)
  let redeemer6 = (5, 5)

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
    // [input1]
    [input1, input2, input3, input4, input5, input6]
  let outputs =
    // [output1]
    [output1, output2, output3, output4, output5, output6]

  let tx = Transaction { ..placeholder(), inputs: inputs, outputs: outputs }

  let ctx1 = ScriptContext { transaction: tx, purpose: Spend(oref1) }
  let ctx2 = ScriptContext { transaction: tx, purpose: Spend(oref2) }
  let ctx3 = ScriptContext { transaction: tx, purpose: Spend(oref3) }
  let ctx4 = ScriptContext { transaction: tx, purpose: Spend(oref4) }
  let ctx5 = ScriptContext { transaction: tx, purpose: Spend(oref5) }
  let ctx6 = ScriptContext { transaction: tx, purpose: Spend(oref6) }

  spend(#"aced", inDatum, redeemer1, ctx1)? && spend(
    #"aced",
    inDatum,
    redeemer2,
    ctx2,
  )? && spend(#"aced", inDatum, redeemer3, ctx3)? && spend(
    #"aced",
    inDatum,
    redeemer4,
    ctx4,
  )? && spend(#"aced", inDatum, redeemer5, ctx5)? && spend(
    #"aced",
    inDatum,
    redeemer6,
    ctx6,
  )?
}
