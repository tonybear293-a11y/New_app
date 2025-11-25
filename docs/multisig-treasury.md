# Multi-signature Treasury Contract

## Problem
Enterprise teams often manage large shared treasuries. A single private key controlling funds is a major security and governance risk. This project implements an on-chain, multi-signature STX treasury where a configurable committee of signers must collectively approve outgoing payments.

## High-level design
- Funds are held directly by the `multisig-treasury` smart contract in STX.
- A committee of *signers* (principals) and an approval *threshold* are configured by the contract owner.
- Any signer can create a payment proposal targeting a specific recipient and amount.
- Multiple signers independently approve or revoke approval for each proposal.
- Once the number of approvals meets or exceeds the threshold, anyone may execute the proposal and the contract transfers STX to the recipient.

This model is suitable for enterprise treasury operations, payroll, vendor payments, and DAO-style committees.

## On-chain model
### Key state
- `owner`: admin principal allowed to reconfigure signers and threshold.
- `signers`: list of principals that are allowed to propose and approve transfers.
- `threshold`: minimum count of signer approvals required to execute a transfer.
- `last-proposal-id`: monotonically increasing ID counter for proposals.
- `proposals` map:
  - key: `uint` proposal ID
  - value: `{ proposer, recipient, amount, executed, memo }`
- `approvals` map:
  - key: `{ proposal-id, signer }`
  - value: `bool` indicating whether this signer approved the proposal.

The contract holds STX directly. Treasury balance is reported by the read-only function `get-treasury-stx-balance`.

### Core functions
- `set-owner(new-owner)` — owner-only; transfers admin rights.
- `configure-signers(new-signers, new-threshold)` — owner-only; sets the committee and required threshold.
- `deposit(amount)` — any account can deposit STX into the treasury.
- `propose-transfer(recipient, amount, memo)` — signer-only; creates a payment proposal.
- `approve(proposal-id)` — signer-only; records the caller's approval for a proposal.
- `revoke-approval(proposal-id)` — signer-only; removes a previously recorded approval.
- `execute(proposal-id)` — executes a fully-approved proposal and transfers STX.

Read-only helpers:
- `get-owner`, `get-signers`, `get-threshold`
- `get-proposal(proposal-id)`, `has-approved(proposal-id, signer)`
- `get-treasury-stx-balance`

## Flows
### 1. Initial setup
1. Contract is deployed; deployer becomes `owner` by default.
2. Owner calls `configure-signers` with a list of principals (e.g. CFO, CEO, Controller) and a threshold (e.g. 2-of-3).

### 2. Depositing funds
1. Any account calls `deposit(amount)` with a non-zero amount.
2. The contract performs `stx-transfer?` from the caller to itself.
3. On success, the treasury's STX balance increases and the function returns `(ok amount)`.

### 3. Creating a payment proposal
1. A signer decides a payment is needed (e.g. vendor invoice, payroll batch).
2. The signer calls `propose-transfer(recipient, amount, memo)`.
3. The contract increments `last-proposal-id`, inserts a new entry into `proposals`, and returns the new proposal ID.

### 4. Approvals & revocations
1. Each signer independently reviews the proposal off-chain (e.g. in an internal system or UI).
2. To approve, they call `approve(proposal-id)`:
   - The contract ensures the proposal exists, is not executed, and caller is a signer.
   - It stores an entry in `approvals` keyed by `{ proposal-id, signer }`.
3. To revoke, they call `revoke-approval(proposal-id)`:
   - The contract deletes the approval entry for that signer and proposal.

The helper `get-approvals-count` (internal) walks the `signers` list and counts approvals. This pattern keeps approval tracking flexible without needing an explicit counter per proposal.

### 5. Executing a payment
1. Once enough signers have approved, anyone may call `execute(proposal-id)`.
2. The contract checks:
   - Proposal exists and is not already executed.
   - Approval count >= `threshold`.
   - Treasury STX balance is at least the proposal amount.
3. If checks pass, the contract:
   - Transfers STX from itself to the recipient.
   - Marks the proposal as `executed = true` to prevent double-spend.

## Error handling and safety
The contract uses explicit error codes:
- `ERR-NOT-OWNER`, `ERR-NOT-SIGNER` — unauthorized callers.
- `ERR-NONZERO-THRESHOLD`, `ERR-INVALID-THRESHOLD` — misconfigured committee.
- `ERR-PROPOSAL-NOT-FOUND`, `ERR-PROPOSAL-EXECUTED` — invalid proposal lifecycle.
- `ERR-ALREADY-APPROVED`, `ERR-NOT-APPROVED` — incorrect approval state.
- `ERR-INSUFFICIENT-APPROVALS` — threshold not yet met.
- `ERR-INSUFFICIENT-TREASURY` — not enough STX to pay.
- `ERR-ZERO-AMOUNT` — prevents zero-value transfers and deposits.

These safeguards ensure that:
- No single signer can drain funds.
- Proposals cannot be double-executed.
- Misconfiguration (e.g. threshold higher than number of signers) is rejected.

## How a UI would interact with the contract
A front-end wallet or internal enterprise dashboard would typically:

- **Display configuration**: call `get-signers`, `get-threshold`, `get-treasury-stx-balance` to show current committee and balance.
- **Show proposals**: index proposal IDs off-chain and call `get-proposal(id)` to fetch details and status.
- **Show approvals**: for each signer and proposal, call `has-approved(id, signer)`.
- **Create proposals**: build a transaction for `propose-transfer(recipient, amount, memo)` from a signer account.
- **Approve / revoke**: build transactions for `approve(id)` or `revoke-approval(id)`.
- **Execute**: when enough approvals exist, send `execute(id)` from any account.

Because all critical checks happen on-chain, even a buggy UI cannot bypass the multisig rules.

## Design choices and limitations
- **Simple STX-only treasury**: the contract holds STX, not SIP-010 tokens; this keeps flows easy to audit.
- **List-based signer set**: signers are stored in a bounded list for predictable gas costs when counting approvals.
- **No proposal expiry**: proposals never expire by default; governance policies can be layered on off-chain.
- **Single threshold**: one global threshold value; per-proposal thresholds could be added in future iterations.

This implementation is intentionally focused on clarity and safety for enterprise treasury governance, while remaining small enough to understand and extend.
