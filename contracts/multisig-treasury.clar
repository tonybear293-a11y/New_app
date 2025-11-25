;; Multi-signature Treasury Contract
;; Enterprise teams need secure fund management with multiple approval requirements.

(define-constant ERR-NOT-OWNER (err u100))
(define-constant ERR-NOT-SIGNER (err u101))
(define-constant ERR-ALREADY-SIGNER (err u102))
(define-constant ERR-NOT-ENABLED (err u103))
(define-constant ERR-INVALID-THRESHOLD (err u104))
(define-constant ERR-NONZERO-THRESHOLD (err u105))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u110))
(define-constant ERR-PROPOSAL-EXECUTED (err u111))
(define-constant ERR-ALREADY-APPROVED (err u112))
(define-constant ERR-NOT-APPROVED (err u113))
(define-constant ERR-INSUFFICIENT-APPROVALS (err u114))
(define-constant ERR-INSUFFICIENT-TREASURY (err u115))
(define-constant ERR-ZERO-AMOUNT (err u116))

(define-constant MAX-SIGNERS u20)
(define-constant MAX-MEMO-SIZE u80)

(define-data-var owner principal tx-sender)

;; Configuration for the multisig committee
(define-data-var signers (list MAX-SIGNERS principal) (list))
(define-data-var threshold uint u0)

;; Proposal identifier nonce
(define-data-var last-proposal-id uint u0)

;; Proposal state
(define-map proposals
  uint
  {
    proposer: principal,
    recipient: principal,
    amount: uint,
    executed: bool,
    memo: (optional (buff 80))
  }
)

;; Approvals per (proposal-id, signer)
(define-map approvals
  { proposal-id: uint, signer: principal }
  bool
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Helpers
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-read-only (is-owner (who principal))
  (is-eq who (var-get owner))
)

(define-read-only (is-signer (who principal))
  (default-to false
    (fold
      (lambda (s acc)
        (or acc (is-eq s who))
      )
      (var-get signers)
      false
    )
  )
)

(define-read-only (get-approvals-count (proposal-id uint))
  (let
    (
      (signers-list (var-get signers))
    )
    (fold
      (lambda (s count)
        (let
          (
            (has-approved (default-to false (map-get? approvals { proposal-id: proposal-id, signer: s })))
          )
          (if has-approved (+ count u1) count)
        )
      )
      signers-list
      u0
    )
  )
)

(define-read-only (get-treasury-balance)
  (stx-get-balance (as-contract tx-sender))
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Admin & configuration
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (set-owner (new-owner principal))
  (begin
    (if (not (is-owner tx-sender)) ERR-NOT-OWNER
      (begin
        (var-set owner new-owner)
        (ok new-owner)
      )
    )
  )
)

(define-public (configure-signers (new-signers (list MAX-SIGNERS principal)) (new-threshold uint))
  (begin
    (if (not (is-owner tx-sender)) ERR-NOT-OWNER
      (if (is-eq new-threshold u0) ERR-NONZERO-THRESHOLD
        (let
          (
            (signer-count (len new-signers))
          )
          (if (or (is-eq signer-count u0) (> new-threshold signer-count)) ERR-INVALID-THRESHOLD
            (begin
              (var-set signers new-signers)
              (var-set threshold new-threshold)
              (ok { signers: new-signers, threshold: new-threshold })
            )
          )
        )
      )
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Treasury functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Simple STX deposit into the treasury contract
(define-public (deposit (amount uint))
  (begin
    (if (is-eq amount u0) ERR-ZERO-AMOUNT
      (let
        (
          (result (stx-transfer? amount tx-sender (as-contract tx-sender)))
        )
        (match result
          ok-val (ok amount)
          err-val (err err-val)
        )
      )
    )
  )
)

;; Create a new payment proposal that requires multisig approval
(define-public (propose-transfer (recipient principal) (amount uint) (memo (optional (buff 80))))
  (begin
    (if (not (is-signer tx-sender)) ERR-NOT-SIGNER
      (if (is-eq amount u0) ERR-ZERO-AMOUNT
        (if (is-eq (var-get threshold) u0) ERR-NOT-ENABLED
          (let
            (
              (current-id (var-get last-proposal-id))
              (next-id (+ current-id u1))
            )
            (begin
              (var-set last-proposal-id next-id)
              (map-set proposals next-id
                {
                  proposer: tx-sender,
                  recipient: recipient,
                  amount: amount,
                  executed: false,
                  memo: memo
                }
              )
              (ok next-id)
            )
          )
        )
      )
    )
  )
)

;; Approve a pending proposal
(define-public (approve (proposal-id uint))
  (let
    (
      (maybe-proposal (map-get? proposals proposal-id))
    )
    (if (is-none maybe-proposal) ERR-PROPOSAL-NOT-FOUND
      (let
        (
          (proposal (unwrap-panic maybe-proposal))
        )
        (if (get executed proposal) ERR-PROPOSAL-EXECUTED
          (if (not (is-signer tx-sender)) ERR-NOT-SIGNER
            (let
              (
                (existing (map-get? approvals { proposal-id: proposal-id, signer: tx-sender }))
              )
              (if (is-some existing) ERR-ALREADY-APPROVED
                (begin
                  (map-set approvals { proposal-id: proposal-id, signer: tx-sender } true)
                  (ok (get-approvals-count proposal-id))
                )
              )
            )
          )
        )
      )
    )
  )
)

;; Revoke approval before execution
(define-public (revoke-approval (proposal-id uint))
  (let
    (
      (maybe-proposal (map-get? proposals proposal-id))
    )
    (if (is-none maybe-proposal) ERR-PROPOSAL-NOT-FOUND
      (let
        (
          (proposal (unwrap-panic maybe-proposal))
        )
        (if (get executed proposal) ERR-PROPOSAL-EXECUTED
          (if (not (is-signer tx-sender)) ERR-NOT-SIGNER
            (let
              (
                (existing (map-get? approvals { proposal-id: proposal-id, signer: tx-sender }))
              )
              (if (is-none existing) ERR-NOT-APPROVED
                (begin
                  (map-delete approvals { proposal-id: proposal-id, signer: tx-sender })
                  (ok (get-approvals-count proposal-id))
                )
              )
            )
          )
        )
      )
    )
  )
)

;; Execute a proposal once enough approvals are collected
(define-public (execute (proposal-id uint))
  (let
    (
      (maybe-proposal (map-get? proposals proposal-id))
    )
    (if (is-none maybe-proposal) ERR-PROPOSAL-NOT-FOUND
      (let
        (
          (proposal (unwrap-panic maybe-proposal))
          (approvals-count (get-approvals-count proposal-id))
          (required (var-get threshold))
        )
        (if (get executed proposal) ERR-PROPOSAL-EXECUTED
          (if (< approvals-count required) ERR-INSUFFICIENT-APPROVALS
            (let
              (
                (amount (get amount proposal))
                (recipient (get recipient proposal))
                (balance (get-treasury-balance))
              )
              (if (< balance amount) ERR-INSUFFICIENT-TREASURY
                (let
                  (
                    (transfer-result (stx-transfer? amount (as-contract tx-sender) recipient))
                  )
                  (match transfer-result
                    ok-val
                      (begin
                        (map-set proposals proposal-id
                          {
                            proposer: (get proposer proposal),
                            recipient: recipient,
                            amount: amount,
                            executed: true,
                            memo: (get memo proposal)
                          }
                        )
                        (ok { proposal-id: proposal-id, amount: amount, recipient: recipient })
                      )
                    err-val (err err-val)
                  )
                )
              )
            )
          )
        )
      )
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Read-only views
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-read-only (get-owner)
  (var-get owner)
)

(define-read-only (get-signers)
  (var-get signers)
)

(define-read-only (get-threshold)
  (var-get threshold)
)

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

(define-read-only (has-approved (proposal-id uint) (signer principal))
  (default-to false (map-get? approvals { proposal-id: proposal-id, signer: signer }))
)

(define-read-only (get-treasury-stx-balance)
  (get-treasury-balance)
)
