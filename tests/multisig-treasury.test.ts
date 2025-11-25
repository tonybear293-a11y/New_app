import { Clarinet, Tx, Chain, Account, types } from "./deps.ts";

Clarinet.test({
  name: "Owner can configure signers and threshold; non-owner cannot",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const alice = accounts.get("alice")!;

    // Deployer configures Alice and Bob as signers with threshold 2
    let block = chain.mineBlock([
      Tx.contractCall(
        "multisig-treasury",
        "configure-signers",
        [
          types.list([
            types.principal(alice.address),
            types.principal(deployer.address),
          ]),
          types.uint(2),
        ],
        deployer.address,
      ),
    ]);

    block.receipts[0].result.expectOk();

    // Non-owner (Alice) cannot reconfigure
    block = chain.mineBlock([
      Tx.contractCall(
        "multisig-treasury",
        "configure-signers",
        [
          types.list([types.principal(alice.address)]),
          types.uint(1),
        ],
        alice.address,
      ),
    ]);

    block.receipts[0].result.expectErr();
  },
});

Clarinet.test({
  name: "Deposits increase treasury balance and zero-amount is rejected",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const alice = accounts.get("alice")!;

    // Configure signers: Alice + deployer, threshold = 2 (required for proposals but not deposit)
    let block = chain.mineBlock([
      Tx.contractCall(
        "multisig-treasury",
        "configure-signers",
        [
          types.list([
            types.principal(alice.address),
            types.principal(deployer.address),
          ]),
          types.uint(2),
        ],
        deployer.address,
      ),
    ]);
    block.receipts[0].result.expectOk();

    // Successful deposit from Alice
    block = chain.mineBlock([
      Tx.contractCall(
        "multisig-treasury",
        "deposit",
        [types.uint(1_000_000)],
        alice.address,
      ),
    ]);

    block.receipts[0].result.expectOk();

    const balance = chain.callReadOnlyFn(
      "multisig-treasury",
      "get-treasury-stx-balance",
      [],
      deployer.address,
    );
    balance.result.expectUint(1_000_000);

    // Zero-amount deposit is rejected
    block = chain.mineBlock([
      Tx.contractCall(
        "multisig-treasury",
        "deposit",
        [types.uint(0)],
        alice.address,
      ),
    ]);
    block.receipts[0].result.expectErr();
  },
});

Clarinet.test({
  name: "Multisig proposal requires threshold approvals and executes payment",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const alice = accounts.get("alice")!;
    const bob = accounts.get("bob")!;

    // Configure Alice and Bob as signers, threshold = 2
    let block = chain.mineBlock([
      Tx.contractCall(
        "multisig-treasury",
        "configure-signers",
        [
          types.list([
            types.principal(alice.address),
            types.principal(bob.address),
          ]),
          types.uint(2),
        ],
        deployer.address,
      ),
    ]);
    block.receipts[0].result.expectOk();

    // Fund the treasury from deployer
    block = chain.mineBlock([
      Tx.contractCall(
        "multisig-treasury",
        "deposit",
        [types.uint(2_000_000)],
        deployer.address,
      ),
    ]);
    block.receipts[0].result.expectOk();

    // Alice creates a transfer proposal paying Bob 1_000_000 µSTX
    block = chain.mineBlock([
      Tx.contractCall(
        "multisig-treasury",
        "propose-transfer",
        [
          types.principal(bob.address),
          types.uint(1_000_000),
          types.some(types.utf8("Payroll Payout")),
        ],
        alice.address,
      ),
    ]);

    const proposalId = block.receipts[0].result.expectOk().expectUint();

    // Single approval is not enough
    block = chain.mineBlock([
      Tx.contractCall(
        "multisig-treasury",
        "approve",
        [types.uint(proposalId)],
        alice.address,
      ),
    ]);
    block.receipts[0].result.expectOk();

    block = chain.mineBlock([
      Tx.contractCall(
        "multisig-treasury",
        "execute",
        [types.uint(proposalId)],
        alice.address,
      ),
    ]);
    block.receipts[0].result.expectErr();

    // Bob provides a second approval
    block = chain.mineBlock([
      Tx.contractCall(
        "multisig-treasury",
        "approve",
        [types.uint(proposalId)],
        bob.address,
      ),
    ]);
    block.receipts[0].result.expectOk();

    // Now execution should succeed
    block = chain.mineBlock([
      Tx.contractCall(
        "multisig-treasury",
        "execute",
        [types.uint(proposalId)],
        deployer.address,
      ),
    ]);
    block.receipts[0].result.expectOk();

    // Proposal is marked executed
    const proposal = chain.callReadOnlyFn(
      "multisig-treasury",
      "get-proposal",
      [types.uint(proposalId)],
      deployer.address,
    );
    const proposalTuple = proposal.result.expectSome().expectTuple();
    proposalTuple["executed"].expectBool(true);
  },
});
