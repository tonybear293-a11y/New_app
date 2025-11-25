// Pseudo-code wiring for the multisig-treasury UI.
// In a real app, you would import Stacks.js, connect a wallet, and build
// transactions that call the contract functions on-chain.

const CONTRACT_ADDRESS = "<DEPLOYER_CONTRACT_ADDRESS_HERE>"; // e.g. ST... in devnet
const CONTRACT_NAME = "multisig-treasury";

async function refreshState() {
  // Here you would call read-only functions using Stacks.js:
  // - get-signers
  // - get-threshold
  // - get-treasury-stx-balance
  // For this demo, we simply show a placeholder.
  document.getElementById("state").textContent =
    "Call read-only functions (get-signers, get-threshold, get-treasury-stx-balance) via Stacks.js and render here.";
}

async function deposit() {
  const amount = Number(document.getElementById("deposit-amount").value || "0");
  alert(
    `This would send a transaction calling ${CONTRACT_NAME}::deposit(${amount}) from the connected wallet.`,
  );
}

async function proposeTransfer() {
  const recipient = document.getElementById("recipient").value.trim();
  const amount = Number(document.getElementById("proposal-amount").value || "0");
  const memo = document.getElementById("memo").value.trim();
  alert(
    `This would call ${CONTRACT_NAME}::propose-transfer(${recipient}, ${amount}, \"${memo}\") from the connected signer.`,
  );
}

async function approve() {
  const id = Number(document.getElementById("proposal-id").value || "0");
  alert(`This would call ${CONTRACT_NAME}::approve(${id}) from the connected signer.`);
}

async function revoke() {
  const id = Number(document.getElementById("proposal-id").value || "0");
  alert(`This would call ${CONTRACT_NAME}::revoke-approval(${id}) from the connected signer.`);
}

async function executeProposal() {
  const id = Number(document.getElementById("proposal-id").value || "0");
  alert(`This would call ${CONTRACT_NAME}::execute(${id}) from any account once approvals >= threshold.`);
}

window.addEventListener("DOMContentLoaded", () => {
  document.getElementById("refresh-state").onclick = refreshState;
  document.getElementById("deposit-btn").onclick = deposit;
  document.getElementById("propose-btn").onclick = proposeTransfer;
  document.getElementById("approve-btn").onclick = approve;
  document.getElementById("revoke-btn").onclick = revoke;
  document.getElementById("execute-btn").onclick = executeProposal;

  refreshState();
});
