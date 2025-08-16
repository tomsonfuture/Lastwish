(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_WILL_NOT_FOUND (err u101))
(define-constant ERR_WILL_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_BENEFICIARY (err u103))
(define-constant ERR_INSUFFICIENT_FUNDS (err u104))
(define-constant ERR_WILL_NOT_READY (err u105))
(define-constant ERR_ALREADY_EXECUTED (err u106))
(define-constant ERR_TESTATOR_STILL_ALIVE (err u107))
(define-constant ERR_INVALID_AMOUNT (err u108))
(define-constant ERR_HEARTBEAT_TOO_RECENT (err u109))
(define-constant ERR_ASSET_NOT_FOUND (err u110))
(define-constant ERR_ASSET_ALREADY_EXISTS (err u111))
(define-constant ERR_INVALID_ASSET_TYPE (err u112))
(define-constant ERR_ASSET_TRANSFER_FAILED (err u113))
(define-constant ERR_INSUFFICIENT_ASSET_BALANCE (err u114))
(define-constant ERR_CONDITION_NOT_MET (err u115))
(define-constant ERR_CONDITION_NOT_FOUND (err u116))
(define-constant ERR_CONDITION_ALREADY_EXISTS (err u117))
(define-constant ERR_INVALID_CONDITION_TYPE (err u118))
(define-constant ERR_VERIFIER_UNAUTHORIZED (err u119))

(define-data-var next-will-id uint u1)
(define-data-var next-asset-id uint u1)
(define-data-var next-condition-id uint u1)

(define-map wills
  { will-id: uint }
  {
    testator: principal,
    total-amount: uint,
    created-at: uint,
    last-heartbeat: uint,
    heartbeat-interval: uint,
    executed: bool,
    beneficiary-count: uint
  }
)

(define-map beneficiaries
  { will-id: uint, beneficiary: principal }
  {
    percentage: uint,
    amount: uint,
    claimed: bool
  }
)

(define-map testator-wills
  { testator: principal }
  { will-id: uint }
)

(define-map digital-assets
  { asset-id: uint }
  {
    will-id: uint,
    asset-type: (string-ascii 20),
    contract-address: principal,
    token-id: (optional uint),
    amount: uint,
    beneficiary: principal,
    claimed: bool,
    metadata: (string-ascii 256)
  }
)

(define-map will-assets
  { will-id: uint, asset-type: (string-ascii 20) }
  { asset-count: uint }
)

(define-map asset-contracts
  { contract-address: principal }
  {
    is-approved: bool,
    asset-type: (string-ascii 20),
    added-at: uint
  }
)

;; Inheritance conditions for beneficiaries
(define-map inheritance-conditions
  { condition-id: uint }
  {
    will-id: uint,
    beneficiary: principal,
    condition-type: (string-ascii 20), ;; "age", "time-lock", "verification"
    threshold-value: uint, ;; age in years, block delay, or verification status
    created-at: uint,
    is-met: bool,
    verifier: (optional principal), ;; for verification conditions
    description: (string-ascii 256)
  }
)

;; Map beneficiaries to their conditions
(define-map beneficiary-conditions
  { will-id: uint, beneficiary: principal }
  { condition-ids: (list 10 uint) }
)

;; Authorized verifiers for external verification conditions
(define-map authorized-verifiers
  { verifier: principal, will-id: uint }
  {
    is-authorized: bool,
    added-by: principal,
    added-at: uint,
    verification-scope: (string-ascii 100)
  }
)

(define-public (create-will (heartbeat-interval uint))
  (let
    (
      (will-id (var-get next-will-id))
      (current-block stacks-block-height)
    )
    (asserts! (> heartbeat-interval u0) ERR_INVALID_AMOUNT)
    (asserts! (is-none (map-get? testator-wills { testator: tx-sender })) ERR_WILL_ALREADY_EXISTS)
    
    (map-set wills
      { will-id: will-id }
      {
        testator: tx-sender,
        total-amount: u0,
        created-at: current-block,
        last-heartbeat: current-block,
        heartbeat-interval: heartbeat-interval,
        executed: false,
        beneficiary-count: u0
      }
    )
    
    (map-set testator-wills
      { testator: tx-sender }
      { will-id: will-id }
    )
    
    (var-set next-will-id (+ will-id u1))
    (ok will-id)
  )
)

(define-public (add-beneficiary (will-id uint) (beneficiary principal) (percentage uint))
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
    )
    (asserts! (is-eq (get testator will-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get executed will-data)) ERR_ALREADY_EXECUTED)
    (asserts! (> percentage u0) ERR_INVALID_AMOUNT)
    (asserts! (<= percentage u100) ERR_INVALID_AMOUNT)
    (asserts! (not (is-eq beneficiary tx-sender)) ERR_INVALID_BENEFICIARY)
    (asserts! (is-none (map-get? beneficiaries { will-id: will-id, beneficiary: beneficiary })) ERR_INVALID_BENEFICIARY)
    
    (map-set beneficiaries
      { will-id: will-id, beneficiary: beneficiary }
      {
        percentage: percentage,
        amount: u0,
        claimed: false
      }
    )
    
    (map-set wills
      { will-id: will-id }
      (merge will-data { beneficiary-count: (+ (get beneficiary-count will-data) u1) })
    )
    
    (ok true)
  )
)

(define-public (deposit-funds (will-id uint) (amount uint))
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
    )
    (asserts! (is-eq (get testator will-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get executed will-data)) ERR_ALREADY_EXECUTED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set wills
      { will-id: will-id }
      (merge will-data { total-amount: (+ (get total-amount will-data) amount) })
    )
    
    (ok true)
  )
)

(define-public (send-heartbeat (will-id uint))
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
      (current-block stacks-block-height)
    )
    (asserts! (is-eq (get testator will-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get executed will-data)) ERR_ALREADY_EXECUTED)
    (asserts! (>= (- current-block (get last-heartbeat will-data)) u1) ERR_HEARTBEAT_TOO_RECENT)
    
    (map-set wills
      { will-id: will-id }
      (merge will-data { last-heartbeat: current-block })
    )
    
    (ok true)
  )
)

(define-public (execute-will (will-id uint))
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
      (current-block stacks-block-height)
      (time-since-heartbeat (- current-block (get last-heartbeat will-data)))
    )
    (asserts! (not (get executed will-data)) ERR_ALREADY_EXECUTED)
    (asserts! (> (get total-amount will-data) u0) ERR_INSUFFICIENT_FUNDS)
    (asserts! (> (get beneficiary-count will-data) u0) ERR_WILL_NOT_READY)
    (asserts! (>= time-since-heartbeat (get heartbeat-interval will-data)) ERR_TESTATOR_STILL_ALIVE)
    
    (map-set wills
      { will-id: will-id }
      (merge will-data { executed: true })
    )
    
    (ok true)
  )
)

(define-public (claim-inheritance (will-id uint))
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
      (beneficiary-data (unwrap! (map-get? beneficiaries { will-id: will-id, beneficiary: tx-sender }) ERR_INVALID_BENEFICIARY))
      (inheritance-amount (/ (* (get total-amount will-data) (get percentage beneficiary-data)) u100))
    )
    (asserts! (get executed will-data) ERR_WILL_NOT_READY)
    (asserts! (not (get claimed beneficiary-data)) ERR_ALREADY_EXECUTED)
    (asserts! (> inheritance-amount u0) ERR_INSUFFICIENT_FUNDS)
    
    (try! (as-contract (stx-transfer? inheritance-amount tx-sender tx-sender)))
    
    (map-set beneficiaries
      { will-id: will-id, beneficiary: tx-sender }
      (merge beneficiary-data { 
        amount: inheritance-amount,
        claimed: true 
      })
    )
    
    (ok inheritance-amount)
  )
)

(define-public (withdraw-funds (will-id uint) (amount uint))
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
    )
    (asserts! (is-eq (get testator will-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get executed will-data)) ERR_ALREADY_EXECUTED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= amount (get total-amount will-data)) ERR_INSUFFICIENT_FUNDS)
    
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    
    (map-set wills
      { will-id: will-id }
      (merge will-data { total-amount: (- (get total-amount will-data) amount) })
    )
    
    (ok true)
  )
)

(define-read-only (get-will (will-id uint))
  (map-get? wills { will-id: will-id })
)

(define-read-only (get-beneficiary (will-id uint) (beneficiary principal))
  (map-get? beneficiaries { will-id: will-id, beneficiary: beneficiary })
)

(define-read-only (get-testator-will (testator principal))
  (map-get? testator-wills { testator: testator })
)

(define-read-only (is-will-executable (will-id uint))
  (match (map-get? wills { will-id: will-id })
    will-data
    (let
      (
        (current-block stacks-block-height)
        (time-since-heartbeat (- current-block (get last-heartbeat will-data)))
      )
      (and
        (not (get executed will-data))
        (> (get total-amount will-data) u0)
        (> (get beneficiary-count will-data) u0)
        (>= time-since-heartbeat (get heartbeat-interval will-data))
      )
    )
    false
  )
)

(define-read-only (get-inheritance-amount (will-id uint) (beneficiary principal))
  (match (map-get? wills { will-id: will-id })
    will-data
    (match (map-get? beneficiaries { will-id: will-id, beneficiary: beneficiary })
      beneficiary-data
      (some (/ (* (get total-amount will-data) (get percentage beneficiary-data)) u100))
      none
    )
    none
  )
)

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender))
)

(define-public (approve-asset-contract (contract-address principal) (asset-type (string-ascii 20)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (or (is-eq asset-type "nft") (is-eq asset-type "fungible")) ERR_INVALID_ASSET_TYPE)
    
    (map-set asset-contracts
      { contract-address: contract-address }
      {
        is-approved: true,
        asset-type: asset-type,
        added-at: stacks-block-height
      }
    )
    
    (ok true)
  )
)

(define-public (deposit-digital-asset 
  (will-id uint)
  (contract-address principal)
  (asset-type (string-ascii 20))
  (token-id (optional uint))
  (amount uint)
  (beneficiary principal)
  (metadata (string-ascii 256))
)
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
      (asset-contract-data (unwrap! (map-get? asset-contracts { contract-address: contract-address }) ERR_ASSET_NOT_FOUND))
      (asset-id (var-get next-asset-id))
      (current-asset-count (default-to u0 (get asset-count (map-get? will-assets { will-id: will-id, asset-type: asset-type }))))
    )
    (asserts! (is-eq (get testator will-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get executed will-data)) ERR_ALREADY_EXECUTED)
    (asserts! (get is-approved asset-contract-data) ERR_ASSET_NOT_FOUND)
    (asserts! (is-eq (get asset-type asset-contract-data) asset-type) ERR_INVALID_ASSET_TYPE)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (not (is-eq beneficiary tx-sender)) ERR_INVALID_BENEFICIARY)
    
    (begin
      (if (is-eq asset-type "nft")
        (begin
          (asserts! (is-some token-id) ERR_INVALID_AMOUNT)
          (asserts! (is-eq amount u1) ERR_INVALID_AMOUNT)
        )
        (begin
          (asserts! (is-none token-id) ERR_INVALID_AMOUNT)
        )
      )
    )
    
    (map-set digital-assets
      { asset-id: asset-id }
      {
        will-id: will-id,
        asset-type: asset-type,
        contract-address: contract-address,
        token-id: token-id,
        amount: amount,
        beneficiary: beneficiary,
        claimed: false,
        metadata: metadata
      }
    )
    
    (map-set will-assets
      { will-id: will-id, asset-type: asset-type }
      { asset-count: (+ current-asset-count u1) }
    )
    
    (var-set next-asset-id (+ asset-id u1))
    (ok asset-id)
  )
)

(define-public (claim-digital-asset (asset-id uint))
  (let
    (
      (asset-data (unwrap! (map-get? digital-assets { asset-id: asset-id }) ERR_ASSET_NOT_FOUND))
      (will-data (unwrap! (map-get? wills { will-id: (get will-id asset-data) }) ERR_WILL_NOT_FOUND))
    )
    (asserts! (get executed will-data) ERR_WILL_NOT_READY)
    (asserts! (is-eq (get beneficiary asset-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get claimed asset-data)) ERR_ALREADY_EXECUTED)
    
    (map-set digital-assets
      { asset-id: asset-id }
      (merge asset-data { claimed: true })
    )
    
    (ok true)
  )
)

(define-public (withdraw-digital-asset (asset-id uint))
  (let
    (
      (asset-data (unwrap! (map-get? digital-assets { asset-id: asset-id }) ERR_ASSET_NOT_FOUND))
      (will-data (unwrap! (map-get? wills { will-id: (get will-id asset-data) }) ERR_WILL_NOT_FOUND))
    )
    (asserts! (is-eq (get testator will-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get executed will-data)) ERR_ALREADY_EXECUTED)
    (asserts! (not (get claimed asset-data)) ERR_ALREADY_EXECUTED)
    
    (map-delete digital-assets { asset-id: asset-id })
    
    (ok true)
  )
)

(define-public (batch-deposit-assets 
  (will-id uint)
  (assets (list 10 {
    contract-address: principal,
    asset-type: (string-ascii 20),
    token-id: (optional uint),
    amount: uint,
    beneficiary: principal,
    metadata: (string-ascii 256)
  }))
)
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
    )
    (asserts! (is-eq (get testator will-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get executed will-data)) ERR_ALREADY_EXECUTED)
    
    (fold process-asset-deposit assets (ok (list)))
  )
)

(define-private (process-asset-deposit 
  (asset {
    contract-address: principal,
    asset-type: (string-ascii 20),
    token-id: (optional uint),
    amount: uint,
    beneficiary: principal,
    metadata: (string-ascii 256)
  })
  (acc (response (list 10 uint) uint))
)
  (ok (list u1 u2 u3))
)

(define-read-only (get-digital-asset (asset-id uint))
  (map-get? digital-assets { asset-id: asset-id })
)

(define-read-only (get-will-asset-count (will-id uint) (asset-type (string-ascii 20)))
  (default-to u0 (get asset-count (map-get? will-assets { will-id: will-id, asset-type: asset-type })))
)

(define-read-only (get-asset-contract-info (contract-address principal))
  (map-get? asset-contracts { contract-address: contract-address })
)

(define-read-only (is-asset-contract-approved (contract-address principal))
  (match (map-get? asset-contracts { contract-address: contract-address })
    contract-data (get is-approved contract-data)
    false
  )
)

;; Create inheritance condition for a beneficiary
(define-public (create-inheritance-condition 
  (will-id uint)
  (beneficiary principal)
  (condition-type (string-ascii 20))
  (threshold-value uint)
  (verifier (optional principal))
  (description (string-ascii 256))
)
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
      (condition-id (var-get next-condition-id))
      (current-conditions (default-to (list) (get condition-ids (map-get? beneficiary-conditions { will-id: will-id, beneficiary: beneficiary }))))
    )
    ;; Validate inputs
    (asserts! (is-eq (get testator will-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get executed will-data)) ERR_ALREADY_EXECUTED)
    (asserts! (is-some (map-get? beneficiaries { will-id: will-id, beneficiary: beneficiary })) ERR_INVALID_BENEFICIARY)
    (asserts! (or (is-eq condition-type "age") (is-eq condition-type "time-lock") (is-eq condition-type "verification")) ERR_INVALID_CONDITION_TYPE)
    (asserts! (> threshold-value u0) ERR_INVALID_AMOUNT)
    
    ;; For verification conditions, verifier must be provided
    (if (is-eq condition-type "verification")
      (asserts! (is-some verifier) ERR_INVALID_CONDITION_TYPE)
      true
    )
    
    ;; Create the condition
    (map-set inheritance-conditions
      { condition-id: condition-id }
      {
        will-id: will-id,
        beneficiary: beneficiary,
        condition-type: condition-type,
        threshold-value: threshold-value,
        created-at: stacks-block-height,
        is-met: false,
        verifier: verifier,
        description: description
      }
    )
    
    ;; Add condition to beneficiary's condition list
    (map-set beneficiary-conditions
      { will-id: will-id, beneficiary: beneficiary }
      { condition-ids: (unwrap! (as-max-len? (append current-conditions condition-id) u10) ERR_INVALID_AMOUNT) }
    )
    
    (var-set next-condition-id (+ condition-id u1))
    (ok condition-id)
  )
)

;; Authorize a verifier for external verification conditions
(define-public (authorize-verifier 
  (will-id uint)
  (verifier principal)
  (verification-scope (string-ascii 100))
)
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
    )
    (asserts! (is-eq (get testator will-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get executed will-data)) ERR_ALREADY_EXECUTED)
    (asserts! (not (is-eq verifier tx-sender)) ERR_INVALID_BENEFICIARY)
    
    (map-set authorized-verifiers
      { verifier: verifier, will-id: will-id }
      {
        is-authorized: true,
        added-by: tx-sender,
        added-at: stacks-block-height,
        verification-scope: verification-scope
      }
    )
    
    (ok true)
  )
)

;; Mark a verification condition as met (called by authorized verifier)
(define-public (verify-condition (condition-id uint))
  (let
    (
      (condition-data (unwrap! (map-get? inheritance-conditions { condition-id: condition-id }) ERR_CONDITION_NOT_FOUND))
      (verifier-data (unwrap! (map-get? authorized-verifiers { verifier: tx-sender, will-id: (get will-id condition-data) }) ERR_VERIFIER_UNAUTHORIZED))
    )
    (asserts! (get is-authorized verifier-data) ERR_VERIFIER_UNAUTHORIZED)
    (asserts! (is-eq (get condition-type condition-data) "verification") ERR_INVALID_CONDITION_TYPE)
    (asserts! (not (get is-met condition-data)) ERR_CONDITION_ALREADY_EXISTS)
    (asserts! (is-eq (some tx-sender) (get verifier condition-data)) ERR_VERIFIER_UNAUTHORIZED)
    
    (map-set inheritance-conditions
      { condition-id: condition-id }
      (merge condition-data { is-met: true })
    )
    
    (ok true)
  )
)

;; Check if all conditions are met for a beneficiary
(define-public (check-conditions (will-id uint) (beneficiary principal))
  (let
    (
      (beneficiary-cond-data (map-get? beneficiary-conditions { will-id: will-id, beneficiary: beneficiary }))
      (current-block stacks-block-height)
    )
    (match beneficiary-cond-data
      cond-data
      (begin
        (fold check-single-condition (get condition-ids cond-data) { all-met: true, current-block: current-block })
        (ok true)
      )
      (ok true) ;; No conditions means all conditions are met
    )
  )
)

;; Helper function to check individual condition
(define-private (check-single-condition 
  (condition-id uint)
  (acc { all-met: bool, current-block: uint })
)
  (if (get all-met acc)
    (match (map-get? inheritance-conditions { condition-id: condition-id })
      condition-data
      (let
        (
          (condition-met
            (if (get is-met condition-data)
              true
              (if (is-eq (get condition-type condition-data) "time-lock")
                (>= (- (get current-block acc) (get created-at condition-data)) (get threshold-value condition-data))
                (if (is-eq (get condition-type condition-data) "age")
                  ;; For age conditions, we assume threshold-value represents block height when beneficiary reaches required age
                  (>= (get current-block acc) (get threshold-value condition-data))
                  false ;; verification conditions must be manually verified
                )
              )
            )
          )
        )
        (merge acc { all-met: condition-met })
      )
      acc ;; condition not found, keep current state
    )
    acc ;; already failed, no need to check more
  )
)

;; Enhanced claim inheritance with condition checking
(define-public (claim-inheritance-with-conditions (will-id uint))
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
      (beneficiary-data (unwrap! (map-get? beneficiaries { will-id: will-id, beneficiary: tx-sender }) ERR_INVALID_BENEFICIARY))
      (inheritance-amount (/ (* (get total-amount will-data) (get percentage beneficiary-data)) u100))
      (conditions-check (unwrap! (check-conditions will-id tx-sender) ERR_CONDITION_NOT_MET))
    )
    (asserts! (get executed will-data) ERR_WILL_NOT_READY)
    (asserts! (not (get claimed beneficiary-data)) ERR_ALREADY_EXECUTED)
    (asserts! (> inheritance-amount u0) ERR_INSUFFICIENT_FUNDS)
    
    ;; Verify all conditions are met
    (asserts! (is-condition-check-passed will-id tx-sender) ERR_CONDITION_NOT_MET)
    
    (try! (as-contract (stx-transfer? inheritance-amount tx-sender tx-sender)))
    
    (map-set beneficiaries
      { will-id: will-id, beneficiary: tx-sender }
      (merge beneficiary-data { 
        amount: inheritance-amount,
        claimed: true 
      })
    )
    
    (ok inheritance-amount)
  )
)

;; Helper function to check if conditions are passed
(define-private (is-condition-check-passed (will-id uint) (beneficiary principal))
  (let
    (
      (beneficiary-cond-data (map-get? beneficiary-conditions { will-id: will-id, beneficiary: beneficiary }))
      (current-block stacks-block-height)
    )
    (match beneficiary-cond-data
      cond-data
      (fold is-single-condition-met (get condition-ids cond-data) true)
      true ;; No conditions means all conditions are met
    )
  )
)

;; Helper to check if a single condition is met
(define-private (is-single-condition-met (condition-id uint) (acc bool))
  (if acc
    (match (map-get? inheritance-conditions { condition-id: condition-id })
      condition-data
      (if (get is-met condition-data)
        true
        (if (is-eq (get condition-type condition-data) "time-lock")
          (>= (- stacks-block-height (get created-at condition-data)) (get threshold-value condition-data))
          (if (is-eq (get condition-type condition-data) "age")
            (>= stacks-block-height (get threshold-value condition-data))
            false
          )
        )
      )
      false
    )
    false
  )
)

;; Read-only functions for condition management
(define-read-only (get-inheritance-condition (condition-id uint))
  (map-get? inheritance-conditions { condition-id: condition-id })
)

(define-read-only (get-beneficiary-conditions (will-id uint) (beneficiary principal))
  (map-get? beneficiary-conditions { will-id: will-id, beneficiary: beneficiary })
)

(define-read-only (get-verifier-authorization (verifier principal) (will-id uint))
  (map-get? authorized-verifiers { verifier: verifier, will-id: will-id })
)

(define-read-only (are-conditions-met (will-id uint) (beneficiary principal))
  (is-condition-check-passed will-id beneficiary)
)




